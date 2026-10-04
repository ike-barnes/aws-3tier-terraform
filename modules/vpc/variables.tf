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
