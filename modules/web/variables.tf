variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  description = "Where the load balancer lives."
  type        = list(string)
}

variable "app_subnet_ids" {
  description = "Where the app servers live (private)."
  type        = list(string)
}

variable "instance_type" {
  type    = string
  default = "t4g.micro"
}

variable "architecture" {
  description = "arm64 for Graviton instance types (t4g, m7g), x86_64 for Intel/AMD (t3, m6i)."
  type        = string
  default     = "arm64"

  validation {
    condition     = contains(["arm64", "x86_64"], var.architecture)
    error_message = "architecture must be arm64 or x86_64."
  }
}

variable "min_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 4
}

variable "desired_capacity" {
  type    = number
  default = 2
}

variable "golden_ami_name_prefix" {
  description = "Use the newest AMI you own whose name starts with this prefix (a Packer golden image). Leave null to use stock Amazon Linux 2023."
  type        = string
  default     = null
}

variable "cpu_target" {
  description = "Target average CPU percent for the Auto Scaling group."
  type        = number
  default     = 50
}
