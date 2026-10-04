variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name" {
  description = "Prefix for every resource name."
  type        = string
  default     = "three-tier-dev"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}
