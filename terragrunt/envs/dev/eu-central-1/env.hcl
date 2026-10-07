locals {
  environment                = "dev"
  region                     = "eu-central-1"
  # *.dev.binbon.ch covers every host on this ALB (api.dev, api-gateway.dev). It's
  # requested with scripts/request-certs.sh and DNS-validated at the registrar.
  # A first-level name (x.binbon.ch) pointed here would need its own certificate.
  alb_certificate_arn             = "arn:aws:acm:eu-central-1:954028443831:certificate/4c3106ed-66d7-4991-987f-de0b05481332"
  alb_additional_certificate_arns = []
  cloudfront_certificate_arn = null
  # TEMPORARY: a new account can't create CloudFront resources until AWS
  # verifies it, so media runs without its distribution and services get an
  # empty CDN_BASE_URL (presigned S3 URLs). Set back to true once verified,
  # then apply media, secrets, and redeploy media/user/video-processing.
  media_cloudfront_enabled = false
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
    password_wo_version   = 2
  }
  # TEMPORARY: dev deploys REPLACE a service's task instead of overlapping it.
  # With the Fargate quota at 6-8 vCPU and 31 x 0.25 = 7.75 wanted, an overlapping
  # deploy has room for one service at a time, so a push touching many services
  # rolled most of them back. With 0 / 100 a deploy needs no spare vCPU; each
  # service is down for a minute or two while its new task starts (until rollback
  # if that task fails). Remove once the quota is raised, back to 100 / 200.
  ecs_deployment = { minimum_healthy_percent = 0, maximum_percent = 100 }
  # TEMPORARY: every service runs at cpu = 256 (0.25 vCPU), down from 512,
  # because a new account's Fargate On-Demand vCPU quota is 6 while the
  # increase to 64 is pending (requested 2026-10-07). 31 x 0.25 = 7.75, which
  # leaves room for one service's deployment at a time. Put it back to 512 once
  # the quota is raised.
  services = {
    api-gateway = { image = "binbon-dev:api-gateway-replace", container_port = 8080, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = ["/api/*", "/health"], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = "api-gateway", task_policy_json = null
    }
    admin-service = { image = "binbon-dev:admin-service-replace", container_port = 8103, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = null, task_policy_json = null
    }
    analytics-service = { image = "binbon-dev:analytics-service-replace", container_port = 8102, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = "analytics-service", task_policy_json = null
    }
    audit-service = { image = "binbon-dev:audit-service-replace", container_port = 8107, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = "audit-service", task_policy_json = null
    }
    auth-service = { image = "binbon-dev:auth-service-replace", container_port = 8081, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev", OTP_FIXED_CODE = "151507"
      }, secret_arns = {
      }, redpanda_user = "auth-service", task_policy_json = null
    }
    call-service = { image = "binbon-dev:call-service-replace", container_port = 8096, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = null, task_policy_json = null
    }
    chat-service = { image = "binbon-dev:chat-service-replace", container_port = 8094, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = "chat-service", task_policy_json = null
    }
    comment-service = { image = "binbon-dev:comment-service-replace", container_port = 8090, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = "comment-service", task_policy_json = null
    }
    device-service = { image = "binbon-dev:device-service-replace", container_port = 8083, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = null, task_policy_json = null
    }
    engagement-service = { image = "binbon-dev:engagement-service-replace", container_port = 8088, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = "engagement-service", task_policy_json = null
    }
    feed-service = { image = "binbon-dev:feed-service-replace", container_port = 8087, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = "feed-service", task_policy_json = null
    }
    fraud-service = { image = "binbon-dev:fraud-service-replace", container_port = 8110, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = null, task_policy_json = null
    }
    gift-service = { image = "binbon-dev:gift-service-replace", container_port = 8104, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = "gift-service", task_policy_json = null
    }
    live-service = { image = "binbon-dev:live-service-replace", container_port = 8100, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = null, task_policy_json = null
    }
    location-service = { image = "binbon-dev:location-service-replace", container_port = 8106, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = null, task_policy_json = null
    }
    media-service = { image = "binbon-dev:media-service-replace", container_port = 8085, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev", MEDIA_PRIVATE_ACCESS_ENABLED = "true"
      }, secret_arns = {
      }, redpanda_user = "media-service", task_policy_json = null
    }
    moderation-service = { image = "binbon-dev:moderation-service-replace", container_port = 8109, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = "moderation-service", task_policy_json = null
    }
    notification-service = { image = "binbon-dev:notification-service-replace", container_port = 8101, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = "notification-service", task_policy_json = null
    }
    payment-service = { image = "binbon-dev:payment-service-replace", container_port = 8098, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = null, task_policy_json = null
    }
    payout-service = { image = "binbon-dev:payout-service-replace", container_port = 8099, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = null, task_policy_json = null
    }
    pk-service = { image = "binbon-dev:pk-service-replace", container_port = 8105, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = "pk-service", task_policy_json = null
    }
    presence-service = { image = "binbon-dev:presence-service-replace", container_port = 8095, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = null, task_policy_json = null
    }
    rbac-service = { image = "binbon-dev:rbac-service-replace", container_port = 8084, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = null, task_policy_json = null
    }
    recommendation-service = { image = "binbon-dev:recommendation-service-replace", container_port = 8089, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = "recommendation-service", task_policy_json = null
    }
    report-service = { image = "binbon-dev:report-service-replace", container_port = 8108, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = "report-service", task_policy_json = null
    }
    search-service = { image = "binbon-dev:search-service-replace", container_port = 8093, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = "search-service", task_policy_json = null
    }
    sticker-service = { image = "binbon-dev:sticker-service-replace", container_port = 8092, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = null, task_policy_json = null
    }
    story-service = { image = "binbon-dev:story-service-replace", container_port = 8091, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = "story-service", task_policy_json = null
    }
    user-service = { image = "binbon-dev:user-service-replace", container_port = 8082, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = "user-service", task_policy_json = null
    }
    video-processing-service = { image = "binbon-dev:video-processing-service-replace", container_port = 8086, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = "video-processing-service", task_policy_json = null
    }
    wallet-service = { image = "binbon-dev:wallet-service-replace", container_port = 8097, cpu = 256, memory = 1024, desired_count = 1, min_count = 1, max_count = 3, path_patterns = [], environment = { APP_ENV = "dev"
      }, secret_arns = {
      }, redpanda_user = "wallet-service", task_policy_json = null
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
    # The 922640336342 account's "binbon-dev-private-link" is stuck deleting:
    # its AWS endpoint sits in that blocked account. Redpanda keeps the name
    # while the deletion runs, so this account's link needs another one.
    private_link_name           = "binbon-dev-pl"
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
        # Added for the messaging/stories/relationships work in the backend
        # (chat-service, media-service, user-service, story-service). No
        # replication_factor: Redpanda Serverless enforces 3 and rejects any
        # explicit value, which mid-apply destroys the topics.
        }, "message.events" = { partitions = 2, configuration = { "cleanup.policy" = "delete", "retention.ms" = "604800000"
        }
        }, "media.events" = { partitions = 2, configuration = { "cleanup.policy" = "delete", "retention.ms" = "604800000"
        }
        }, "relationship.events" = { partitions = 2, configuration = { "cleanup.policy" = "delete", "retention.ms" = "604800000"
        }
        # notification.events is the notification-REQUEST bus: chat-service and
        # story-service publish requests, notification-service consumes them.
        }, "notification.events" = { partitions = 2, configuration = { "cleanup.policy" = "delete", "retention.ms" = "604800000"
        }
        }, "audio.events" = { partitions = 2, configuration = { "cleanup.policy" = "delete", "retention.ms" = "604800000"
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
      "user-service" = { password_wo_version = 1, topic_permissions = { "user.events" = ["WRITE", "READ", "DESCRIBE"], "follow.events" = ["WRITE", "DESCRIBE"], "relationship.events" = ["WRITE", "DESCRIBE"]
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
      "notification-service" = { password_wo_version = 1, topic_permissions = { "follow.events" = ["READ", "DESCRIBE"], "notification.events" = ["READ", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = []
      }
      "analytics-service" = { password_wo_version = 1, topic_permissions = { "follow.events" = ["READ", "DESCRIBE"], "video.events" = ["READ", "DESCRIBE"], "gift.events" = ["READ", "DESCRIBE"], "story.events" = ["READ", "DESCRIBE"]
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
      "media-service" = { password_wo_version = 1, topic_permissions = { "video.events" = ["WRITE", "READ", "DESCRIBE"], "media.events" = ["WRITE", "DESCRIBE"], "audio.events" = ["WRITE", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = []
      }
      "video-processing-service" = { password_wo_version = 1, topic_permissions = { "video.events" = ["WRITE", "READ", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = []
      }
      "recommendation-service" = { password_wo_version = 1, topic_permissions = { "video.events" = ["READ", "DESCRIBE"], "post.events" = ["READ", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = []
      }
      "gift-service" = { password_wo_version = 1, topic_permissions = { "gift.events" = ["WRITE", "READ", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = []
      }
      "wallet-service" = { password_wo_version = 1, topic_permissions = { "gift.events" = ["WRITE", "DESCRIBE"], "notification.events" = ["WRITE", "DESCRIBE"]
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
      "story-service" = { password_wo_version = 1, topic_permissions = { "story.events" = ["WRITE", "DESCRIBE"], "notification.events" = ["WRITE", "DESCRIBE"], "follow.events" = ["READ", "DESCRIBE"], "message.events" = ["READ", "DESCRIBE"], "media.events" = ["READ", "DESCRIBE"], "relationship.events" = ["READ", "DESCRIBE"]
        }, group_permissions = {
        }, cluster_permissions = []
      }
      # Produces every chat message event, and consumes its own stream for the
      # group inbox fan-out and search indexing (chat-fanout, chat-search) plus
      # the story, media, relationship, follow and moderation streams. No group
      # ACLs: rskafka reads partitions directly rather than joining a consumer
      # group, so the chat-* names are internal labels, not Kafka groups.
      "chat-service" = { password_wo_version = 1, topic_permissions = { "message.events" = ["WRITE", "READ", "DESCRIBE"], "notification.events" = ["WRITE", "DESCRIBE"], "story.events" = ["READ", "DESCRIBE"], "media.events" = ["READ", "DESCRIBE"], "relationship.events" = ["READ", "DESCRIBE"], "follow.events" = ["READ", "DESCRIBE"], "moderation.events" = ["WRITE", "READ", "DESCRIBE"]
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