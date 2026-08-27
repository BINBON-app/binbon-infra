-- Binbon — ClickHouse schema (Phase 4). Append-only event tables + materialized
-- rollups. MergeTree family, monthly partitions for cheap pruning + TTL retention.
-- Note: the four spec'd view-event streams (video/reel/story/live) share an identical
-- schema, so storage is ONE `view_events` MergeTree keyed by `content_type` (the
-- correct columnar/OLAP design — 4 byte-identical tables would be an anti-pattern,
-- forcing 4x merges/MVs). The named tables still EXIST as VIEWs over it, so every
-- spec'd object is queryable.

CREATE DATABASE IF NOT EXISTS binbon_analytics;

-- ===========================================================================
-- View events (unified storage; per-type VIEWs below)
-- ===========================================================================
CREATE TABLE IF NOT EXISTS binbon_analytics.view_events
(
    event_time   DateTime64(3) DEFAULT now64(3),
    content_type LowCardinality(String),   -- video | reel | story | live
    content_id   UUID,
    owner_id     UUID,
    user_id      UUID,
    watch_ms     UInt32 DEFAULT 0,
    completed    UInt8 DEFAULT 0,
    source       LowCardinality(String),   -- for_you | following | search | profile | live
    device       LowCardinality(String),   -- ios | android
    country      LowCardinality(String),
    app_version  LowCardinality(String)
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY (content_type, content_id, event_time)
TTL toDateTime(event_time) + INTERVAL 365 DAY;

CREATE VIEW IF NOT EXISTS binbon_analytics.video_view_events AS
    SELECT * FROM binbon_analytics.view_events WHERE content_type = 'video';
CREATE VIEW IF NOT EXISTS binbon_analytics.reel_view_events AS
    SELECT * FROM binbon_analytics.view_events WHERE content_type = 'reel';
CREATE VIEW IF NOT EXISTS binbon_analytics.story_view_events AS
    SELECT * FROM binbon_analytics.view_events WHERE content_type = 'story';
CREATE VIEW IF NOT EXISTS binbon_analytics.live_view_events AS
    SELECT * FROM binbon_analytics.view_events WHERE content_type = 'live';

-- ===========================================================================
-- Distinct event streams
-- ===========================================================================
CREATE TABLE IF NOT EXISTS binbon_analytics.engagement_events
(
    event_time DateTime64(3) DEFAULT now64(3),
    kind       LowCardinality(String),     -- like | unlike | share | save | comment | follow
    user_id    UUID,
    target_id  UUID,
    owner_id   UUID,
    country    LowCardinality(String)
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY (kind, target_id, event_time)
TTL toDateTime(event_time) + INTERVAL 365 DAY;

CREATE TABLE IF NOT EXISTS binbon_analytics.gift_events
(
    event_time   DateTime64(3) DEFAULT now64(3),
    gift_id      UUID,
    sender_id    UUID,
    recipient_id UUID,
    coins        UInt64,
    payout_coins UInt64,
    context      LowCardinality(String),   -- live | post | dm
    context_id   String
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY (recipient_id, event_time);

CREATE TABLE IF NOT EXISTS binbon_analytics.payment_events
(
    event_time  DateTime64(3) DEFAULT now64(3),
    user_id     UUID,
    provider    LowCardinality(String),    -- apple_iap | google_play | stripe | local
    kind        LowCardinality(String),    -- intent | succeeded | failed | refund
    coins       UInt64,
    amount_cents Int64,
    currency    LowCardinality(String),
    provider_ref String
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY (provider, event_time);

CREATE TABLE IF NOT EXISTS binbon_analytics.user_activity_events
(
    event_time DateTime64(3) DEFAULT now64(3),
    user_id    UUID,
    action     LowCardinality(String),     -- session_start | session_end | screen_view | ...
    screen     LowCardinality(String),
    device     LowCardinality(String),
    country    LowCardinality(String)
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY (user_id, event_time)
TTL toDateTime(event_time) + INTERVAL 180 DAY;

CREATE TABLE IF NOT EXISTS binbon_analytics.search_events
(
    event_time  DateTime64(3) DEFAULT now64(3),
    user_id     UUID,
    query       String,
    result_count UInt32,
    clicked_id  UUID,
    kind        LowCardinality(String)      -- users | videos | hashtags | sounds | live
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_time)
TTL toDateTime(event_time) + INTERVAL 180 DAY;

CREATE TABLE IF NOT EXISTS binbon_analytics.call_events
(
    event_time   DateTime64(3) DEFAULT now64(3),
    call_id      UUID,
    caller_id    UUID,
    callee_id    UUID,
    kind         LowCardinality(String),    -- audio | video
    state        LowCardinality(String),    -- started | accepted | missed | ended
    duration_secs UInt32 DEFAULT 0
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_time);

-- ===========================================================================
-- Aggregates (rollup targets + materialized views that feed them)
-- ===========================================================================
-- Trending: per-content daily counters, summed at merge time.
CREATE TABLE IF NOT EXISTS binbon_analytics.trending_aggregates
(
    day          Date,
    content_type LowCardinality(String),
    content_id   UUID,
    owner_id     UUID,
    views        UInt64,
    watch_ms     UInt64,
    completes    UInt64
)
ENGINE = SummingMergeTree
PARTITION BY toYYYYMM(day)
ORDER BY (content_type, content_id, day)
TTL day + INTERVAL 120 DAY;

CREATE MATERIALIZED VIEW IF NOT EXISTS binbon_analytics.mv_trending TO binbon_analytics.trending_aggregates AS
SELECT
    toDate(event_time) AS day,
    content_type,
    content_id,
    owner_id,
    count()            AS views,
    sum(watch_ms)      AS watch_ms,
    sum(completed)     AS completes
FROM binbon_analytics.view_events
GROUP BY day, content_type, content_id, owner_id;

-- Creator daily stats (dashboard).
CREATE TABLE IF NOT EXISTS binbon_analytics.creator_daily_stats
(
    day        Date,
    creator_id UUID,
    views      UInt64,
    watch_ms   UInt64
)
ENGINE = SummingMergeTree
PARTITION BY toYYYYMM(day)
ORDER BY (creator_id, day)
TTL day + INTERVAL 730 DAY;

CREATE MATERIALIZED VIEW IF NOT EXISTS binbon_analytics.mv_creator_daily TO binbon_analytics.creator_daily_stats AS
SELECT
    toDate(event_time) AS day,
    owner_id           AS creator_id,
    count()            AS views,
    sum(watch_ms)      AS watch_ms
FROM binbon_analytics.view_events
GROUP BY day, creator_id;
