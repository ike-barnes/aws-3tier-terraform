variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "db_subnet_ids" {
  description = "The private database subnets (no internet route)."
  type        = list(string)
}

variable "app_security_group_id" {
  description = "Only this security group may connect to the database."
  type        = string
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "engine_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "16"
}

variable "multi_az" {
  description = "A standby in a second AZ. Off in the lab to save cost."
  type        = bool
  default     = false
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "username" {
  type    = string
  default = "appadmin"
}
