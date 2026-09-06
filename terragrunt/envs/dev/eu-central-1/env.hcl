locals {
  environment                = "dev"
  region                     = "eu-central-1"
  account_id                 = "803817915623"
  domain_name                = null
  route53_zone_id            = null
  alb_certificate_arn        = null
  cloudfront_certificate_arn = null
  opensearch = {
    instance_type  = "t3.small.search"
    instance_count = 1
    volume_size_gb = 10
  }
  clickhouse = {
    region                = "eu-central-1"
    num_replicas          = 1
    min_replica_memory_gb = 8
    max_replica_memory_gb = 8
    idle_scaling          = true
    password_wo_version   = 1
  }
  services = {
    api-gateway = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:api-gateway-replace", container_port = 8080, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = ["/api/*"], environment = { APP_ENV = "dev"
      }, secret_arns = { REDPANDA_SASL_PASSWORD = "arn:aws:secretsmanager:eu-central-1:803817915623:secret:binbon-dev-redpanda-api-gateway-8iakcw"
      }, redpanda_user = "api-gateway", task_policy_json = null
    }
    admin-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:admin-service-replace", container_port = 8103, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = null, task_policy_json = null
    }
    analytics-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:analytics-service-replace", container_port = 8102, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = { REDPANDA_SASL_PASSWORD = "arn:aws:secretsmanager:eu-central-1:803817915623:secret:binbon-dev-redpanda-analytics-service-IgdPq5"
      }, redpanda_user = "analytics-service", task_policy_json = null
    }
    audit-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:audit-service-replace", container_port = 8107, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = { REDPANDA_SASL_PASSWORD = "arn:aws:secretsmanager:eu-central-1:803817915623:secret:binbon-dev-redpanda-audit-service-eMkkUX"
      }, redpanda_user = "audit-service", task_policy_json = null
    }
    auth-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:auth-service-replace", container_port = 8081, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = { REDPANDA_SASL_PASSWORD = "arn:aws:secretsmanager:eu-central-1:803817915623:secret:binbon-dev-redpanda-auth-service-tZYgGw"
      }, redpanda_user = "auth-service", task_policy_json = null
    }
    call-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:call-service-replace", container_port = 8096, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = null, task_policy_json = null
    }
    chat-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:chat-service-replace", container_port = 8094, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = null, task_policy_json = null
    }
    comment-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:comment-service-replace", container_port = 8090, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = { REDPANDA_SASL_PASSWORD = "arn:aws:secretsmanager:eu-central-1:803817915623:secret:binbon-dev-redpanda-comment-service-6sydAn"
      }, redpanda_user = "comment-service", task_policy_json = null
    }
    device-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:device-service-replace", container_port = 8083, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = null, task_policy_json = null
    }
    engagement-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:engagement-service-replace", container_port = 8088, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = { REDPANDA_SASL_PASSWORD = "arn:aws:secretsmanager:eu-central-1:803817915623:secret:binbon-dev-redpanda-engagement-service-fTWrdY"
      }, redpanda_user = "engagement-service", task_policy_json = null
    }
    feed-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:feed-service-replace", container_port = 8087, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = { REDPANDA_SASL_PASSWORD = "arn:aws:secretsmanager:eu-central-1:803817915623:secret:binbon-dev-redpanda-feed-service-ulDSF5"
      }, redpanda_user = "feed-service", task_policy_json = null
    }
    fraud-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:fraud-service-replace", container_port = 8110, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = null, task_policy_json = null
    }
    gift-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:gift-service-replace", container_port = 8104, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = { REDPANDA_SASL_PASSWORD = "arn:aws:secretsmanager:eu-central-1:803817915623:secret:binbon-dev-redpanda-gift-service-qgJImI"
      }, redpanda_user = "gift-service", task_policy_json = null
    }
    live-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:live-service-replace", container_port = 8100, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = null, task_policy_json = null
    }
    location-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:location-service-replace", container_port = 8106, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = null, task_policy_json = null
    }
    media-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:media-service-replace", container_port = 8085, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = { REDPANDA_SASL_PASSWORD = "arn:aws:secretsmanager:eu-central-1:803817915623:secret:binbon-dev-redpanda-media-service-gGx9rH"
      }, redpanda_user = "media-service", task_policy_json = null
    }
    moderation-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:moderation-service-replace", container_port = 8109, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = { REDPANDA_SASL_PASSWORD = "arn:aws:secretsmanager:eu-central-1:803817915623:secret:binbon-dev-redpanda-moderation-service-MrSlnl"
      }, redpanda_user = "moderation-service", task_policy_json = null
    }
    notification-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:notification-service-replace", container_port = 8101, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = { REDPANDA_SASL_PASSWORD = "arn:aws:secretsmanager:eu-central-1:803817915623:secret:binbon-dev-redpanda-notification-service-WMtKxJ"
      }, redpanda_user = "notification-service", task_policy_json = null
    }
    payment-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:payment-service-replace", container_port = 8098, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = null, task_policy_json = null
    }
    payout-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:payout-service-replace", container_port = 8099, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = null, task_policy_json = null
    }
    pk-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:pk-service-replace", container_port = 8105, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = { REDPANDA_SASL_PASSWORD = "arn:aws:secretsmanager:eu-central-1:803817915623:secret:binbon-dev-redpanda-pk-service-S1Zzr9"
      }, redpanda_user = "pk-service", task_policy_json = null
    }
    presence-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:presence-service-replace", container_port = 8095, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = null, task_policy_json = null
    }
    rbac-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:rbac-service-replace", container_port = 8084, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = null, task_policy_json = null
    }
    recommendation-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:recommendation-service-replace", container_port = 8089, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = { REDPANDA_SASL_PASSWORD = "arn:aws:secretsmanager:eu-central-1:803817915623:secret:binbon-dev-redpanda-recommendation-service-mILzDj"
      }, redpanda_user = "recommendation-service", task_policy_json = null
    }
    report-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:report-service-replace", container_port = 8108, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = { REDPANDA_SASL_PASSWORD = "arn:aws:secretsmanager:eu-central-1:803817915623:secret:binbon-dev-redpanda-report-service-ZcUyw0"
      }, redpanda_user = "report-service", task_policy_json = null
    }
    search-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:search-service-replace", container_port = 8093, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = { REDPANDA_SASL_PASSWORD = "arn:aws:secretsmanager:eu-central-1:803817915623:secret:binbon-dev-redpanda-search-service-p1LMwL"
      }, redpanda_user = "search-service", task_policy_json = null
    }
    sticker-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:sticker-service-replace", container_port = 8092, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = null, task_policy_json = null
    }
    story-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:story-service-replace", container_port = 8091, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = { REDPANDA_SASL_PASSWORD = "arn:aws:secretsmanager:eu-central-1:803817915623:secret:binbon-dev-redpanda-story-service-gQt2Pp"
      }, redpanda_user = "story-service", task_policy_json = null
    }
    user-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:user-service-replace", container_port = 8082, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = { REDPANDA_SASL_PASSWORD = "arn:aws:secretsmanager:eu-central-1:803817915623:secret:binbon-dev-redpanda-user-service-OfZJnq"
      }, redpanda_user = "user-service", task_policy_json = null
    }
    video-processing-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:video-processing-service-replace", container_port = 8086, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = { REDPANDA_SASL_PASSWORD = "arn:aws:secretsmanager:eu-central-1:803817915623:secret:binbon-dev-redpanda-video-processing-service-3KBM5R"
      }, redpanda_user = "video-processing-service", task_policy_json = null
    }
    wallet-service = { image = "803817915623.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev:wallet-service-replace", container_port = 8097, cpu = 512, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = { REDPANDA_SASL_PASSWORD = "arn:aws:secretsmanager:eu-central-1:803817915623:secret:binbon-dev-redpanda-wallet-service-LwFXEY"
      }, redpanda_user = "wallet-service", task_policy_json = null
    }
  }
  # Full schema for the 5 Keyspaces-backed services (chat, comment, engagement,
  # feed, story), all sharing the one binbon_dev_app keyspace. Mirrors each
  # service's own `TABLES` const in crates/<service>/src/db.rs exactly - DDL is
  # owned by infra (Terraform) against Keyspaces, per that file's own comments,
  # since the app's MIGRATE_ON_START is forced false there.
  keyspaces_tables = {
    # story-service
    stories_by_user = {
      columns = [
        { name = "user_id", type = "uuid" },
        { name = "created_at", type = "timestamp" },
        { name = "story_id", type = "uuid" },
        { name = "media_id", type = "uuid" },
        { name = "kind", type = "text" },
        { name = "visibility", type = "text" },
      ]
      partition_key  = ["user_id"]
      clustering_key = [{ name = "created_at", order = "DESC" }, { name = "story_id", order = "DESC" }]
    }
    stories_by_id = {
      columns = [
        { name = "story_id", type = "uuid" },
        { name = "owner_id", type = "uuid" },
        { name = "media_id", type = "uuid" },
        { name = "kind", type = "text" },
        { name = "visibility", type = "text" },
        { name = "created_at", type = "timestamp" },
      ]
      partition_key = ["story_id"]
    }
    story_views = {
      columns = [
        { name = "story_id", type = "uuid" },
        { name = "viewer_id", type = "uuid" },
        { name = "viewed_at", type = "timestamp" },
        { name = "reaction", type = "text" },
      ]
      partition_key  = ["story_id"]
      clustering_key = [{ name = "viewer_id" }]
    }
    story_view_counters = {
      columns = [
        { name = "story_id", type = "uuid" },
        { name = "views_count", type = "counter" },
      ]
      partition_key = ["story_id"]
    }

    # feed-service
    videos_by_id = {
      columns = [
        { name = "video_id", type = "uuid" },
        { name = "owner_id", type = "uuid" },
        { name = "kind", type = "text" },
        { name = "caption", type = "text" },
        { name = "visibility", type = "text" },
        { name = "media_id", type = "uuid" },
        { name = "hls_url", type = "text" },
        { name = "thumbnail_url", type = "text" },
        { name = "duration_ms", type = "int" },
        { name = "sound_id", type = "uuid" },
        { name = "hashtags", type = "set<text>" },
        { name = "created_at", type = "timestamp" },
        { name = "published_at", type = "timestamp" },
      ]
      partition_key = ["video_id"]
    }
    videos_by_user = {
      columns = [
        { name = "owner_id", type = "uuid" },
        { name = "created_at", type = "timestamp" },
        { name = "video_id", type = "uuid" },
        { name = "kind", type = "text" },
        { name = "visibility", type = "text" },
      ]
      partition_key  = ["owner_id"]
      clustering_key = [{ name = "created_at", order = "DESC" }, { name = "video_id", order = "DESC" }]
    }
    feed_by_user = {
      columns = [
        { name = "user_id", type = "uuid" },
        { name = "bucket", type = "int" },
        { name = "inserted_at", type = "timestamp" },
        { name = "video_id", type = "uuid" },
        { name = "owner_id", type = "uuid" },
        { name = "score", type = "double" },
      ]
      partition_key  = ["user_id", "bucket"]
      clustering_key = [{ name = "inserted_at", order = "DESC" }, { name = "video_id", order = "DESC" }]
    }
    followers_by_user = {
      columns = [
        { name = "user_id", type = "uuid" },
        { name = "follower_id", type = "uuid" },
        { name = "created_at", type = "timestamp" },
      ]
      partition_key  = ["user_id"]
      clustering_key = [{ name = "follower_id" }]
    }
    following_by_user = {
      columns = [
        { name = "user_id", type = "uuid" },
        { name = "followee_id", type = "uuid" },
        { name = "created_at", type = "timestamp" },
      ]
      partition_key  = ["user_id"]
      clustering_key = [{ name = "followee_id" }]
    }
    consumer_offsets = {
      columns = [
        { name = "consumer", type = "text" },
        { name = "topic", type = "text" },
        { name = "partition", type = "int" },
        { name = "next_offset", type = "bigint" },
      ]
      partition_key  = ["consumer", "topic"]
      clustering_key = [{ name = "partition" }]
    }

    # comment-service
    comments_by_video = {
      columns = [
        { name = "video_id", type = "uuid" },
        { name = "created_at", type = "timestamp" },
        { name = "comment_id", type = "uuid" },
        { name = "author_id", type = "uuid" },
        { name = "body", type = "text" },
        { name = "sticker_id", type = "uuid" },
        { name = "likes_count", type = "int" },
      ]
      partition_key  = ["video_id"]
      clustering_key = [{ name = "created_at", order = "DESC" }, { name = "comment_id", order = "DESC" }]
    }
    replies_by_comment = {
      columns = [
        { name = "comment_id", type = "uuid" },
        { name = "created_at", type = "timestamp" },
        { name = "reply_id", type = "uuid" },
        { name = "author_id", type = "uuid" },
        { name = "body", type = "text" },
        { name = "sticker_id", type = "uuid" },
      ]
      partition_key  = ["comment_id"]
      clustering_key = [{ name = "created_at", order = "ASC" }, { name = "reply_id", order = "ASC" }]
    }
    comment_meta = {
      columns = [
        { name = "comment_id", type = "uuid" },
        { name = "video_id", type = "uuid" },
        { name = "author_id", type = "uuid" },
      ]
      partition_key = ["comment_id"]
    }
    comment_counters = {
      columns = [
        { name = "video_id", type = "uuid" },
        { name = "comments_count", type = "counter" },
      ]
      partition_key = ["video_id"]
    }
    comment_likes_by_comment = {
      columns = [
        { name = "comment_id", type = "uuid" },
        { name = "user_id", type = "uuid" },
        { name = "liked_at", type = "timestamp" },
      ]
      partition_key  = ["comment_id"]
      clustering_key = [{ name = "user_id" }]
    }
    comment_like_counters = {
      columns = [
        { name = "comment_id", type = "uuid" },
        { name = "likes_count", type = "counter" },
      ]
      partition_key = ["comment_id"]
    }

    # engagement-service
    likes_by_video = {
      columns = [
        { name = "video_id", type = "uuid" },
        { name = "user_id", type = "uuid" },
        { name = "liked_at", type = "timestamp" },
      ]
      partition_key  = ["video_id"]
      clustering_key = [{ name = "user_id" }]
    }
    likes_by_user = {
      columns = [
        { name = "user_id", type = "uuid" },
        { name = "liked_at", type = "timestamp" },
        { name = "video_id", type = "uuid" },
      ]
      partition_key  = ["user_id"]
      clustering_key = [{ name = "liked_at", order = "DESC" }, { name = "video_id", order = "DESC" }]
    }
    saves_by_video = {
      columns = [
        { name = "video_id", type = "uuid" },
        { name = "user_id", type = "uuid" },
        { name = "saved_at", type = "timestamp" },
      ]
      partition_key  = ["video_id"]
      clustering_key = [{ name = "user_id" }]
    }
    saves_by_user = {
      columns = [
        { name = "user_id", type = "uuid" },
        { name = "saved_at", type = "timestamp" },
        { name = "video_id", type = "uuid" },
      ]
      partition_key  = ["user_id"]
      clustering_key = [{ name = "saved_at", order = "DESC" }, { name = "video_id", order = "DESC" }]
    }
    video_counters = {
      columns = [
        { name = "video_id", type = "uuid" },
        { name = "likes_count", type = "counter" },
        { name = "views_count", type = "counter" },
        { name = "comments_count", type = "counter" },
        { name = "shares_count", type = "counter" },
        { name = "saves_count", type = "counter" },
      ]
      partition_key = ["video_id"]
    }
    shares_by_video = {
      columns = [
        { name = "video_id", type = "uuid" },
        { name = "user_id", type = "uuid" },
        { name = "shared_at", type = "timestamp" },
      ]
      partition_key  = ["video_id"]
      clustering_key = [{ name = "user_id" }]
    }
    views_seen_by_video = {
      columns = [
        { name = "video_id", type = "uuid" },
        { name = "user_id", type = "uuid" },
        { name = "first_viewed_at", type = "timestamp" },
      ]
      partition_key  = ["video_id"]
      clustering_key = [{ name = "user_id" }]
    }
    video_views_by_video = {
      columns = [
        { name = "video_id", type = "uuid" },
        { name = "bucket", type = "int" },
        { name = "viewed_at", type = "timestamp" },
        { name = "view_id", type = "timeuuid" },
        { name = "user_id", type = "uuid" },
        { name = "watch_ms", type = "int" },
      ]
      partition_key  = ["video_id", "bucket"]
      clustering_key = [{ name = "viewed_at", order = "DESC" }, { name = "view_id", order = "DESC" }]
    }
    user_interactions = {
      columns = [
        { name = "user_id", type = "uuid" },
        { name = "ts", type = "timestamp" },
        { name = "interaction_id", type = "timeuuid" },
        { name = "kind", type = "text" },
        { name = "target_id", type = "uuid" },
      ]
      partition_key  = ["user_id"]
      clustering_key = [{ name = "ts", order = "DESC" }, { name = "interaction_id", order = "DESC" }]
    }

    # chat-service
    messages_by_conversation = {
      columns = [
        { name = "conversation_id", type = "uuid" },
        { name = "bucket", type = "int" },
        { name = "created_at", type = "timestamp" },
        { name = "message_id", type = "uuid" },
        { name = "sender_id", type = "uuid" },
        { name = "kind", type = "text" },
        { name = "body", type = "text" },
        { name = "media_id", type = "uuid" },
        { name = "duration_ms", type = "int" },
      ]
      partition_key  = ["conversation_id", "bucket"]
      clustering_key = [{ name = "created_at", order = "DESC" }, { name = "message_id", order = "DESC" }]
    }
    conversations_by_user = {
      columns = [
        { name = "user_id", type = "uuid" },
        { name = "conversation_id", type = "uuid" },
        { name = "other_user_id", type = "uuid" },
        { name = "last_body", type = "text" },
        { name = "last_kind", type = "text" },
        { name = "last_message_at", type = "timestamp" },
      ]
      partition_key  = ["user_id"]
      clustering_key = [{ name = "conversation_id" }]
    }
    conv_received = {
      columns = [
        { name = "user_id", type = "uuid" },
        { name = "conversation_id", type = "uuid" },
        { name = "n", type = "counter" },
      ]
      partition_key  = ["user_id"]
      clustering_key = [{ name = "conversation_id" }]
    }
    read_marks = {
      columns = [
        { name = "user_id", type = "uuid" },
        { name = "conversation_id", type = "uuid" },
        { name = "read_count", type = "bigint" },
        { name = "last_read_at", type = "timestamp" },
      ]
      partition_key  = ["user_id"]
      clustering_key = [{ name = "conversation_id" }]
    }
  }
  cognito = {
    hosted_domain_prefix          = "binbon-dev-803817915623"
    custom_domain                 = null
    custom_domain_certificate_arn = null
    callback_urls                 = ["http://localhost:3000/callback"]
    logout_urls                   = ["http://localhost:3000/"]
    mfa_configuration             = "OPTIONAL"
    allow_self_signup             = true
    generate_client_secret        = false
    create_identity_pool          = false
    groups = { users = { description = "Default users", precedence = 100
      }, moderators = { description = "Moderators", precedence = 50
      }, admins = { description = "Administrators", precedence = 1
      }
    }
    api_scopes = { read = "Read application data", write = "Write application data"
    }
    lambda_triggers = {
    }

  }
  # OpenVPN Access Server - standing operator access into the VPC (Aurora,
  # Redis, OpenSearch, etc.) via a real VPN instead of ad-hoc SSM tunnels.
  # AMI is region-specific and tied to the AWS Marketplace product code
  # 3ihdqli79gl9v2jnlzs6nq60h - re-look-up if deploying to a new region:
  #   aws ec2 describe-images --owners aws-marketplace \
  #     --filters "Name=name,Values=*OpenVPN*Access*Server*"
  vpn = {
    ami_id        = "ami-02ec271df508ac2e6"
    instance_type = "t3.small"
    key_name      = null
    # Defaults open (0.0.0.0/0) for SSH (22) and the admin web UI (943) -
    # tighten to your own IP(s) once the instance is up.
    admin_cidrs = ["0.0.0.0/0"]
  }
  redpanda = {
    region                      = "eu-central-1"
    enable_private_link         = true
    public_networking           = "STATE_DISABLED"
    private_networking          = "STATE_ENABLED"
    allow_cluster_deletion      = true
    allow_private_link_deletion = true
    allow_topic_deletion        = true
    allow_user_deletion         = true
    allow_acl_deletion          = true
    topics = {
      "user-events" = { partitions = 3, configuration = { "cleanup.policy" = "delete", "retention.ms" = "604800000"
        }
        }, notifications = { partitions = 3, configuration = { "cleanup.policy" = "delete", "retention.ms" = "259200000"
        }
        }, "user.events" = { partitions = 2, configuration = { "cleanup.policy" = "delete", "retention.ms" = "604800000"
        }
        }, "follow.events" = { partitions = 2, configuration = { "cleanup.policy" = "delete", "retention.ms" = "604800000"
        }
        }, "video.events" = { partitions = 2, configuration = { "cleanup.policy" = "delete", "retention.ms" = "604800000"
        }
        }, "post.events" = { partitions = 2, configuration = { "cleanup.policy" = "delete", "retention.ms" = "604800000"
        }
        }, "gift.events" = { partitions = 2, configuration = { "cleanup.policy" = "delete", "retention.ms" = "604800000"
        }
        }, "audit.events" = { partitions = 2, configuration = { "cleanup.policy" = "delete", "retention.ms" = "604800000"
        }
        }, "story.events" = { partitions = 2, configuration = { "cleanup.policy" = "delete", "retention.ms" = "604800000"
        }
        }, "moderation.events" = { partitions = 2, configuration = { "cleanup.policy" = "delete", "retention.ms" = "604800000"
        }
        }, "pk.events" = { partitions = 2, configuration = { "cleanup.policy" = "delete", "retention.ms" = "604800000"
        }
      }
    }
    service_users = {
      "api-gateway" = { password_wo_version = 1, topic_permissions = { "user-events" = ["WRITE", "DESCRIBE"], notifications = ["WRITE", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = []
      }
      "auth-service" = { password_wo_version = 1, topic_permissions = { "user.events" = ["WRITE", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = []
      }
      "user-service" = { password_wo_version = 1, topic_permissions = { "user.events" = ["WRITE", "READ", "DESCRIBE"], "follow.events" = ["WRITE", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = []
      }
      "search-service" = { password_wo_version = 1, topic_permissions = { "user.events" = ["READ", "DESCRIBE"], "post.events" = ["READ", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = []
      }
      "feed-service" = { password_wo_version = 1, topic_permissions = { "follow.events" = ["READ", "DESCRIBE"], "post.events" = ["WRITE", "READ", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = []
      }
      "notification-service" = { password_wo_version = 1, topic_permissions = { "follow.events" = ["READ", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = []
      }
      "analytics-service" = { password_wo_version = 1, topic_permissions = { "follow.events" = ["READ", "DESCRIBE"], "video.events" = ["READ", "DESCRIBE"], "gift.events" = ["READ", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = []
      }
      "comment-service" = { password_wo_version = 1, topic_permissions = { "video.events" = ["WRITE", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = []
      }
      "engagement-service" = { password_wo_version = 1, topic_permissions = { "video.events" = ["WRITE", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = []
      }
      "media-service" = { password_wo_version = 1, topic_permissions = { "video.events" = ["WRITE", "READ", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = []
      }
      "video-processing-service" = { password_wo_version = 1, topic_permissions = { "video.events" = ["WRITE", "READ", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = []
      }
      "recommendation-service" = { password_wo_version = 1, topic_permissions = { "video.events" = ["READ", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = []
      }
      "gift-service" = { password_wo_version = 1, topic_permissions = { "gift.events" = ["WRITE", "READ", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = []
      }
      "wallet-service" = { password_wo_version = 1, topic_permissions = { "gift.events" = ["WRITE", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = []
      }
      "moderation-service" = { password_wo_version = 1, topic_permissions = { "audit.events" = ["WRITE", "DESCRIBE"], "moderation.events" = ["WRITE", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = []
      }
      "report-service" = { password_wo_version = 1, topic_permissions = { "audit.events" = ["WRITE", "DESCRIBE"], "moderation.events" = ["WRITE", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = []
      }
      "audit-service" = { password_wo_version = 1, topic_permissions = { "audit.events" = ["READ", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = []
      }
      "story-service" = { password_wo_version = 1, topic_permissions = { "story.events" = ["WRITE", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = []
      }
      "pk-service" = { password_wo_version = 1, topic_permissions = { "pk.events" = ["WRITE", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = []
      }
      # Read-only credential for external tooling (Kafka UI, Redpanda Console,
      # kcat, monitoring) - not one of the 18 per-service application users.
      # SCRAM works with these tools today, unlike the app services which are
      # stuck on rskafka's PLAIN-only support pending the cluster-side change.
      "monitoring-readonly" = { password_wo_version = 1, topic_permissions = {
          "user.events" = ["READ", "DESCRIBE"], "follow.events" = ["READ", "DESCRIBE"], "video.events" = ["READ", "DESCRIBE"],
          "post.events" = ["READ", "DESCRIBE"], "gift.events" = ["READ", "DESCRIBE"], "audit.events" = ["READ", "DESCRIBE"],
          "story.events" = ["READ", "DESCRIBE"], "moderation.events" = ["READ", "DESCRIBE"], "pk.events" = ["READ", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = ["DESCRIBE"]
      }
    }
  }
}