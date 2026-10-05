output "endpoint" {
  description = "Hostname the app connects to"
  value       = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "username" {
  value = aws_db_instance.this.username
}

output "secret_arn" {
  description = "Secrets Manager secret holding the master password"
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "kms_key_arn" {
  value = aws_kms_key.db.arn
}

output "security_group_id" {
  value = aws_security_group.db.id
}
