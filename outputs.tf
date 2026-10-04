output "app_url" {
  description = "Open this in a browser"
  value       = "http://${module.web.alb_dns_name}"
}

output "alb_dns_name" {
  value = module.web.alb_dns_name
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "asg_name" {
  value = module.web.asg_name
}
