-- Binbon — Amazon Keyspaces schema (migrated from migrations/scylla/0001_social_keyspace.cql).
--
-- This is the SAME query-first data model as the ScyllaDB schema; the ONLY change
-- required for Amazon Keyspaces is the keyspace-creation statement (Keyspaces
-- manages replication itself and rejects a NetworkTopologyStrategy/SimpleStrategy
-- replication_factor clause — it uses SingleRegionStrategy, RF=3 across 3 AZs).
--
-- Everything else — counter tables, default_time_to_live, set<text>, compound
-- partition keys, clustering order — is natively supported by Keyspaces.
--
-- OPERATIONAL NOTES (Keyspaces differs from Scylla here):
--   * DDL is ASYNCHRONOUS. `CREATE TABLE` returns before the table is queryable;
--     each table transitions CREATING -> ACTIVE. Apply this file with the
--     wait-for-ACTIVE loop in scripts/keyspaces/apply-schema.sh, NOT a bare
--     `cqlsh -f`, or the first read/prepare against a still-CREATING table fails.
--   * Table CAPACITY (provisioned + autoscaling, per your DevOps decision), PITR,
--     encryption, and tags are Keyspaces table properties set by the infrastructure
--     layer (Terraform, owned by ops) — NOT expressed in this portable CQL. Applied
--     via cqlsh, tables default to on-demand; Terraform overrides to provisioned.
--   * Hot single-partition throughput is capped at ~1000 WCU / 3000 RCU per
--     partition. The bucketed partition keys below (yyyymm / yyyymmdd / yyyymmddHH)
--     already spread the hottest streams; the per-video counter rows
--     (video_counters, comment_counters, story_view_counters) are the remaining
--     hot-partition exposure under viral load — size their table capacity for it.
--
-- Keyspaces auth for whoever applies this: cqlsh with the SigV4 plugin, or
-- service-specific credentials over TLS on cassandra.<region>.amazonaws.com:9142.

CREATE KEYSPACE IF NOT EXISTS binbon
  WITH REPLICATION = {'class': 'SingleRegionStrategy'};

USE binbon;

-- ---------------------------------------------------------------------------
-- Videos / reels / long video
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS videos_by_id (
    video_id     uuid PRIMARY KEY,
    owner_id     uuid,
    kind         text,
    caption      text,
    visibility   text,
    media_id     uuid,
    hls_url      text,
    thumbnail_url text,
    duration_ms  int,
    sound_id     uuid,
    hashtags     set<text>,
    created_at   timestamp,
    published_at timestamp
);

CREATE TABLE IF NOT EXISTS videos_by_user (
    owner_id   uuid,
    created_at timestamp,
    video_id   uuid,
    kind       text,
    visibility text,
    PRIMARY KEY ((owner_id), created_at, video_id)
) WITH CLUSTERING ORDER BY (created_at DESC, video_id DESC);

CREATE TABLE IF NOT EXISTS feed_by_user (
    user_id    uuid,
    bucket     int,
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

-- Denormalized counters. Keyspaces supports counter tables; counter updates are
-- not idempotent on retry, so app code gates them behind a single-partition LWT.
CREATE TABLE IF NOT EXISTS video_counters (
    video_id      uuid PRIMARY KEY,
    likes_count   counter,
    views_count   counter,
    comments_count counter,
    shares_count  counter,
    saves_count   counter
);

CREATE TABLE IF NOT EXISTS shares_by_video (
    video_id   uuid,
    user_id    uuid,
    shared_at  timestamp,
    PRIMARY KEY ((video_id), user_id)
);

CREATE TABLE IF NOT EXISTS views_seen_by_video (
    video_id        uuid,
    user_id         uuid,
    first_viewed_at timestamp,
    PRIMARY KEY ((video_id), user_id)
);

CREATE TABLE IF NOT EXISTS video_views_by_video (
    video_id  uuid,
    bucket    int,
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
    kind           text,
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
-- Social graph
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
-- Stories (TTL)
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
) WITH default_time_to_live = 172800;   -- 48h

-- ---------------------------------------------------------------------------
-- Chat
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS conversations_by_user (
    user_id         uuid,
    conversation_id uuid,
    other_user_id   uuid,
    last_body       text,
    last_kind       text,
    last_message_at timestamp,
    PRIMARY KEY ((user_id), conversation_id)
);

CREATE TABLE IF NOT EXISTS conv_received (
    user_id         uuid,
    conversation_id uuid,
    n               counter,
    PRIMARY KEY ((user_id), conversation_id)
);

CREATE TABLE IF NOT EXISTS read_marks (
    user_id         uuid,
    conversation_id uuid,
    read_count      bigint,
    last_read_at    timestamp,
    PRIMARY KEY ((user_id), conversation_id)
);

CREATE TABLE IF NOT EXISTS messages_by_conversation (
    conversation_id uuid,
    bucket          int,
    created_at      timestamp,
    message_id      uuid,
    sender_id       uuid,
    kind            text,
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
    bucket     int,
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
) WITH default_time_to_live = 43200;    -- 12h

-- ---------------------------------------------------------------------------
-- Runtime tables the owning services also create (mirror of each service's db.rs)
-- ---------------------------------------------------------------------------

-- engagement-service: saves
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

-- comment-service: parent lookup + counters + comment likes
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

-- story-service: by-id lookup + per-story view counter
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

-- Kafka/Redpanda consumer offsets for the Scylla-backed consumer services.
CREATE TABLE IF NOT EXISTS consumer_offsets (
    consumer    text,
    topic       text,
    partition   int,
    next_offset bigint,
    PRIMARY KEY ((consumer, topic), partition)
);
