output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "asg_name" {
  value = aws_autoscaling_group.app.name
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "app_security_group_id" {
  value = aws_security_group.app.id
}

output "target_group_arn" {
  value = aws_lb_target_group.app.arn
}

output "app_role_name" {
  description = "Instance role, so the root module can grant it extra permissions"
  value       = aws_iam_role.app.name
}
