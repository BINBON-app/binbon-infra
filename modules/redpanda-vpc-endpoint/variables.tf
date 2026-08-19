variable "name" {
  description = "Environment/resource name prefix"
  type        = string
}

variable "vpc_id" {
  description = "VPC where the Redpanda PrivateLink endpoint will be created"
  type        = string
}

variable "subnet_ids" {
  description = "Candidate application subnet IDs. The module automatically selects only subnets in AZ IDs supported by Redpanda."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "At least one subnet ID must be provided."
  }
}

variable "task_security_group_id" {
  description = "Security group used by ECS tasks that require access to Redpanda"
  type        = string
}

variable "service_name" {
  description = "AWS PrivateLink endpoint service name returned by Redpanda"
  type        = string

  validation {
    condition = (
      var.service_name != null &&
      trimspace(var.service_name) != ""
    )

    error_message = "service_name must contain the Redpanda PrivateLink endpoint service name."
  }
}

variable "service_availability_zone_ids" {
  description = "AWS Availability Zone IDs supported by the Redpanda PrivateLink endpoint service"
  type        = list(string)

  validation {
    condition     = length(var.service_availability_zone_ids) > 0
    error_message = "At least one Redpanda PrivateLink Availability Zone ID must be supplied."
  }
}

variable "private_dns_enabled" {
  description = "Enable private DNS for the Redpanda VPC interface endpoint"
  type        = bool
  default     = true
}

variable "ingress_rules" {
  description = "Ports that ECS tasks may use to access Redpanda"

  type = map(object({
    description = string
    from_port   = number
    to_port     = number
  }))

  default = {
    kafka = {
      description = "Redpanda Kafka bootstrap and brokers"
      from_port   = 9092
      to_port     = 9095
    }

    schema_registry = {
      description = "Redpanda Schema Registry"
      from_port   = 8081
      to_port     = 8081
    }

    dataplane_api = {
      description = "Redpanda Data Plane API"
      from_port   = 443
      to_port     = 443
    }
  }
}

variable "tags" {
  description = "Tags applied to resources"
  type        = map(string)
  default     = {}
}