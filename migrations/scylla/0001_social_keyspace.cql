-- Binbon — ScyllaDB schema (Phase 4). High-scale social/content activity.
-- Query-first modeling: one table per access pattern; partition keys bound partition
-- size; hot/unbounded streams (messages, live chat, views) use a time BUCKET in the
-- partition key to avoid wide partitions. Counters live in dedicated counter tables.
-- NetworkTopologyStrategy + RF=3 in prod; tune per DC.

CREATE KEYSPACE IF NOT EXISTS binbon
  WITH replication = {'class': 'NetworkTopologyStrategy', 'replication_factor': 3}
  AND durable_writes = true;

USE binbon;

-- ---------------------------------------------------------------------------
-- Videos / reels / long video
-- ---------------------------------------------------------------------------
-- Lookup by id (canonical metadata mirror; source-of-truth keys live in media PG).
CREATE TABLE IF NOT EXISTS videos_by_id (
    video_id     uuid PRIMARY KEY,
    owner_id     uuid,
    kind         text,            -- reel | long_video
    caption      text,
    visibility   text,            -- public | followers | private
    media_id     uuid,
    hls_url      text,
    thumbnail_url text,
    duration_ms  int,
    sound_id     uuid,
    hashtags     set<text>,
    created_at   timestamp,
    published_at timestamp
);

-- A creator's videos, newest first.
CREATE TABLE IF NOT EXISTS videos_by_user (
    owner_id   uuid,
    created_at timestamp,
    video_id   uuid,
    kind       text,
    visibility text,
    PRIMARY KEY ((owner_id), created_at, video_id)
) WITH CLUSTERING ORDER BY (created_at DESC, video_id DESC);

-- Precomputed home/following timeline (fan-out-on-write). Bucketed by yyyymm to bound.
CREATE TABLE IF NOT EXISTS feed_by_user (
    user_id    uuid,
    bucket     int,              -- yyyymm
    inserted_at timestamp,
    video_id   uuid,
    owner_id   uuid,
    score      double,
    PRIMARY KEY ((user_id, bucket), inserted_at, video_id)
) WITH CLUSTERING ORDER BY (inserted_at DESC, video_id DESC);

-- ---------------------------------------------------------------------------
-- Engagement
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS likes_by_video (
    video_id  uuid,
    user_id   uuid,
    liked_at  timestamp,
    PRIMARY KEY ((video_id), user_id)
);

CREATE TABLE IF NOT EXISTS likes_by_user (
    user_id   uuid,
    liked_at  timestamp,
    video_id  uuid,
    PRIMARY KEY ((user_id), liked_at, video_id)
) WITH CLUSTERING ORDER BY (liked_at DESC, video_id DESC);

-- Denormalized counters (Scylla counters require a dedicated table).
CREATE TABLE IF NOT EXISTS video_counters (
    video_id      uuid PRIMARY KEY,
    likes_count   counter,
    views_count   counter,
    comments_count counter,
    shares_count  counter,
    saves_count   counter
);

-- CMT-12: per-(video,user) share gate (an LWT INSERT gates shares_count, so one
-- user can't self-loop to inflate shares / trending). Mirrors likes_by_video.
CREATE TABLE IF NOT EXISTS shares_by_video (
    video_id   uuid,
    user_id    uuid,
    shared_at  timestamp,
    PRIMARY KEY ((video_id), user_id)
);

-- CMT-12/CMT-36: per-(video,user) FIRST-view gate — views_count becomes unique
-- viewers (the LWT INSERT applies once per user), so a refresh/self-loop can't pump
-- the counter or the reco signal.
CREATE TABLE IF NOT EXISTS views_seen_by_video (
    video_id        uuid,
    user_id         uuid,
    first_viewed_at timestamp,
    PRIMARY KEY ((video_id), user_id)
);

-- Raw view rows for recency/anti-replay; aggregate analytics live in ClickHouse.
-- Bucketed (yyyymmdd) — views are extremely high volume.
CREATE TABLE IF NOT EXISTS video_views_by_video (
    video_id  uuid,
    bucket    int,              -- yyyymmdd
    viewed_at timestamp,
    view_id   timeuuid,
    user_id   uuid,
    watch_ms  int,
    PRIMARY KEY ((video_id, bucket), viewed_at, view_id)
) WITH CLUSTERING ORDER BY (viewed_at DESC, view_id DESC)
  AND default_time_to_live = 7776000;   -- 90d raw retention

CREATE TABLE IF NOT EXISTS user_interactions (
    user_id        uuid,
    ts             timestamp,
    interaction_id timeuuid,
    kind           text,        -- view | like | share | comment | follow
    target_id      uuid,
    PRIMARY KEY ((user_id), ts, interaction_id)
) WITH CLUSTERING ORDER BY (ts DESC, interaction_id DESC)
  AND default_time_to_live = 2592000;   -- 30d

-- ---------------------------------------------------------------------------
-- Comments
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS comments_by_video (
    video_id   uuid,
    created_at timestamp,
    comment_id uuid,
    author_id  uuid,
    body       text,
    sticker_id uuid,
    likes_count int,
    PRIMARY KEY ((video_id), created_at, comment_id)
) WITH CLUSTERING ORDER BY (created_at DESC, comment_id DESC);

CREATE TABLE IF NOT EXISTS replies_by_comment (
    comment_id uuid,
    created_at timestamp,
    reply_id   uuid,
    author_id  uuid,
    body       text,
    sticker_id uuid,
    PRIMARY KEY ((comment_id), created_at, reply_id)
) WITH CLUSTERING ORDER BY (created_at ASC, reply_id ASC);

-- ---------------------------------------------------------------------------
-- Social graph (canonical edges also in user PG; these are the scale-read mirror)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS followers_by_user (
    user_id     uuid,
    follower_id uuid,
    created_at  timestamp,
    PRIMARY KEY ((user_id), follower_id)
);

CREATE TABLE IF NOT EXISTS following_by_user (
    user_id     uuid,
    followee_id uuid,
    created_at  timestamp,
    PRIMARY KEY ((user_id), followee_id)
);

-- ---------------------------------------------------------------------------
-- Stories (24h TTL)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stories_by_user (
    user_id    uuid,
    created_at timestamp,
    story_id   uuid,
    media_id   uuid,
    kind       text,
    visibility text,
    PRIMARY KEY ((user_id), created_at, story_id)
) WITH CLUSTERING ORDER BY (created_at DESC, story_id DESC)
  AND default_time_to_live = 86400;     -- 24h

CREATE TABLE IF NOT EXISTS story_views (
    story_id  uuid,
    viewer_id uuid,
    viewed_at timestamp,
    reaction  text,
    PRIMARY KEY ((story_id), viewer_id)
) WITH default_time_to_live = 172800;   -- 48h (outlives the story for the owner)

-- ---------------------------------------------------------------------------
-- Chat
-- ---------------------------------------------------------------------------
-- CMT-29: keyed by conversation_id (matches chat-service runtime); newest-first
-- ordering is applied app-side after the read. (Was previously mis-specified here
-- with a last_message_at clustering key that the service does not use.)
-- CMT-31: chat-service pages this partition with a bounded LIMIT + a cursor on
-- the `conversation_id` clustering key (WHERE user_id = ? AND conversation_id > ?),
-- so a heavy user lists conversations page-by-page instead of loading the whole
-- partition. last_message_at stays a plain column (a Scylla clustering cursor must
-- be a clustering key); each bounded page is re-sorted by last_message_at app-side.
CREATE TABLE IF NOT EXISTS conversations_by_user (
    user_id         uuid,
    conversation_id uuid,
    other_user_id   uuid,
    last_body       text,
    last_kind       text,
    last_message_at timestamp,
    PRIMARY KEY ((user_id), conversation_id)
);

-- Per-(user, conversation) received-message counter (drives unread).
CREATE TABLE IF NOT EXISTS conv_received (
    user_id         uuid,
    conversation_id uuid,
    n               counter,
    PRIMARY KEY ((user_id), conversation_id)
);

-- Per-(user, conversation) read mark (unread = conv_received.n − read_count).
CREATE TABLE IF NOT EXISTS read_marks (
    user_id         uuid,
    conversation_id uuid,
    read_count      bigint,
    last_read_at    timestamp,
    PRIMARY KEY ((user_id), conversation_id)
);

-- Bucketed by yyyymm: a busy conversation must not become an unbounded partition.
CREATE TABLE IF NOT EXISTS messages_by_conversation (
    conversation_id uuid,
    bucket          int,        -- yyyymm
    created_at      timestamp,
    message_id      uuid,
    sender_id       uuid,
    kind            text,       -- text | voice | image | video | sticker
    body            text,
    media_id        uuid,
    duration_ms     int,
    PRIMARY KEY ((conversation_id, bucket), created_at, message_id)
) WITH CLUSTERING ORDER BY (created_at DESC, message_id DESC);

-- ---------------------------------------------------------------------------
-- Live
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS live_streams_by_creator (
    creator_id uuid,
    started_at timestamp,
    stream_id  uuid,
    title      text,
    state      text,
    PRIMARY KEY ((creator_id), started_at, stream_id)
) WITH CLUSTERING ORDER BY (started_at DESC, stream_id DESC);

CREATE TABLE IF NOT EXISTS live_chat_by_stream (
    stream_id  uuid,
    bucket     int,             -- yyyymmddHH (live chat is bursty)
    created_at timestamp,
    message_id timeuuid,
    user_id    uuid,
    body       text,
    PRIMARY KEY ((stream_id, bucket), created_at, message_id)
) WITH CLUSTERING ORDER BY (created_at ASC, message_id ASC)
  AND default_time_to_live = 604800;    -- 7d

CREATE TABLE IF NOT EXISTS live_viewers_by_stream (
    stream_id uuid,
    user_id   uuid,
    joined_at timestamp,
    PRIMARY KEY ((stream_id), user_id)
) WITH default_time_to_live = 43200;    -- 12h safety TTL

-- ---------------------------------------------------------------------------
-- CMT-29: tables the services create at runtime (their in-code bootstrap) that
-- were missing from this canonical schema. On a fresh prod cluster (where the
-- migration Job applies this file and per-service MIGRATE_ON_START is off) their
-- absence crashed those services on startup. Definitions mirror the owning
-- service's `db.rs` exactly.
-- ---------------------------------------------------------------------------

-- engagement-service: saves (mirror of likes; the per-user table gates the counter)
CREATE TABLE IF NOT EXISTS saves_by_video (
    video_id uuid,
    user_id  uuid,
    saved_at timestamp,
    PRIMARY KEY ((video_id), user_id)
);
CREATE TABLE IF NOT EXISTS saves_by_user (
    user_id  uuid,
    saved_at timestamp,
    video_id uuid,
    PRIMARY KEY ((user_id), saved_at, video_id)
) WITH CLUSTERING ORDER BY (saved_at DESC, video_id DESC);

-- comment-service: parent lookup + per-video/per-comment counters + comment likes
CREATE TABLE IF NOT EXISTS comment_meta (
    comment_id uuid PRIMARY KEY,
    video_id   uuid,
    author_id  uuid
);
CREATE TABLE IF NOT EXISTS comment_counters (
    video_id       uuid PRIMARY KEY,
    comments_count counter
);
CREATE TABLE IF NOT EXISTS comment_likes_by_comment (
    comment_id uuid,
    user_id    uuid,
    liked_at   timestamp,
    PRIMARY KEY ((comment_id), user_id)
);
CREATE TABLE IF NOT EXISTS comment_like_counters (
    comment_id  uuid PRIMARY KEY,
    likes_count counter
);

-- story-service: by-id lookup + per-story view counter (counter tables cannot carry
-- a TTL, so the tiny counter row outlives the 24h story harmlessly).
CREATE TABLE IF NOT EXISTS stories_by_id (
    story_id   uuid PRIMARY KEY,
    owner_id   uuid,
    media_id   uuid,
    kind       text,
    visibility text,
    created_at timestamp
) WITH default_time_to_live = 86400;
CREATE TABLE IF NOT EXISTS story_view_counters (
    story_id    uuid PRIMARY KEY,
    views_count counter
);

-- Kafka/Redpanda consumer offsets for the Scylla-backed consumer services
-- (feed/engagement/etc.): one row per (consumer, topic, partition).
CREATE TABLE IF NOT EXISTS consumer_offsets (
    consumer    text,
    topic       text,
    partition   int,
    next_offset bigint,
    PRIMARY KEY ((consumer, topic), partition)
);
