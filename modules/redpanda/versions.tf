terraform {
  required_version = ">= 1.6.0"
  required_providers {
    redpanda = {
      source  = "redpanda-data/redpanda"
      version = "~> 2.1"

    }

  }
}
