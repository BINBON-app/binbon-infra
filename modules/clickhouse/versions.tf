terraform {
  required_version = ">= 1.6.0"
  required_providers {
    clickhouse = {
      source  = "ClickHouse/clickhouse"
      version = ">= 1.0.0"
    }
  }
}
