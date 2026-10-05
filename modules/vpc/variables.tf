variable "name" {
  type = string
}

variable "cidr" {
  type = string
}

variable "az_count" {
  description = "How many availability zones to spread across."
  type        = number
  default     = 2
}

variable "interface_endpoints" {
  description = "AWS services reached privately through interface endpoints instead of the NAT gateway."
  type        = list(string)
  default     = ["ssm", "ssmmessages", "ec2messages", "secretsmanager"]
}
