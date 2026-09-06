variable "name" {
  type = string
}
variable "vpc_id" {
  type = string
}
variable "public_subnet_id" {
  type = string
}
variable "ami_id" {
  type        = string
  description = "OpenVPN Access Server marketplace AMI (product code 3ihdqli79gl9v2jnlzs6nq60h). Region-specific - re-look-up via `aws ec2 describe-images --owners aws-marketplace --filters Name=name,Values='*OpenVPN*Access*Server*'` if deploying elsewhere."
}
variable "instance_type" {
  type    = string
  default = "t3.small"
}
variable "key_name" {
  type        = string
  default     = null
  description = "EC2 key pair for SSH access. Optional: the instance profile gives SSM Session Manager access without one. Do NOT rely on the web UI as a fallback - it does not exist until ovpn-init has run."
}
# The VPN instance joins this SAME security group so it inherits exactly the
# access ECS tasks already have to Aurora/Redis/OpenSearch/etc. (those
# resources' security groups allow ingress FROM this group) - no new
# data-tier rules needed. Connected VPN clients reach internal resources
# through the instance's own NAT'd traffic.
variable "app_security_group_id" {
  type        = string
  description = "The ECS tasks' security group ID (modules/alb output task_security_group_id) - joining it grants the VPN instance the same internal access ECS tasks have."
}
variable "admin_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDRs allowed to reach SSH (22) and the OpenVPN admin web UI (943). Defaults open - tighten to your own IP(s) once the instance is up."
}
variable "tags" {
  type    = map(string)
  default = {}
}
