# Latest Amazon Linux 2023 for the chosen CPU architecture, looked up
# from AWS's public SSM parameter so the AMI is never hard-coded.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${var.architecture}"
}

# The newest golden image built by Packer, if one is requested.
data "aws_ami" "golden" {
  count       = var.golden_ami_name_prefix == null ? 0 : 1
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["${var.golden_ami_name_prefix}*"]
  }

  filter {
    name   = "architecture"
    values = [var.architecture]
  }
}

locals {
  ami_id = var.golden_ami_name_prefix == null ? data.aws_ssm_parameter.al2023.insecure_value : data.aws_ami.golden[0].id
}

# ------------------------------------------------------------------
# Security groups, chained: internet -> ALB -> app. The app servers
# accept traffic ONLY from the load balancer, and there is no SSH
# rule anywhere. Admin access is through SSM Session Manager.
# ------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Load balancer: HTTP from the internet"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-alb" }
}

resource "aws_security_group" "app" {
  name        = "${var.name}-app"
  description = "App servers: HTTP from the load balancer only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-app" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from anywhere"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to app servers only"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "HTTP from the load balancer only"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

resource "aws_vpc_security_group_egress_rule" "app_out" {
  security_group_id = aws_security_group.app.id
  description       = "Outbound for updates and SSM, through the NAT gateway"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ------------------------------------------------------------------
# Instance role: just enough for SSM Session Manager.
# ------------------------------------------------------------------
resource "aws_iam_role" "app" {
  name = "${var.name}-app"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.name}-app"
  role = aws_iam_role.app.name
}

# ------------------------------------------------------------------
# Launch template: the blueprint for every app server.
# ------------------------------------------------------------------
resource "aws_launch_template" "app" {
  name_prefix   = "${var.name}-app-"
  image_id      = local.ami_id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.app.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  # replace() strips Windows line endings, which would break the script.
  user_data = base64encode(replace(file("${path.module}/user_data.sh"), "\r\n", "\n"))

  # One-minute CloudWatch metrics, so scaling reacts in minutes, not ten.
  monitoring {
    enabled = true
  }

  # IMDSv2 only: blocks the metadata-theft trick used in SSRF attacks.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.name}-app" }
  }
}

# ------------------------------------------------------------------
# Application Load Balancer in the public subnets.
# ------------------------------------------------------------------
resource "aws_lb" "this" {
  name                       = "${var.name}-alb"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.public_subnet_ids
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "app" {
  name                 = "${var.name}-tg"
  port                 = 80
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = "/"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ------------------------------------------------------------------
# Auto Scaling group across both private app subnets. If an instance
# fails its load balancer health check, it's replaced automatically.
# ------------------------------------------------------------------
resource "aws_autoscaling_group" "app" {
  name                      = "${var.name}-app"
  min_size                  = var.min_size
  max_size                  = var.max_size
  desired_capacity          = var.desired_capacity
  vpc_zone_identifier       = var.app_subnet_ids
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 120

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  # Changing the launch template rolls out new instances gradually,
  # keeping at least half the fleet serving traffic.
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-app"
    propagate_at_launch = true
  }
}

# ------------------------------------------------------------------
# Target tracking: AWS adds instances when average CPU stays above
# the target and removes them when it drops, within min/max size.
# ------------------------------------------------------------------
resource "aws_autoscaling_policy" "cpu" {
  name                      = "${var.name}-cpu-target"
  autoscaling_group_name    = aws_autoscaling_group.app.name
  policy_type               = "TargetTrackingScaling"
  estimated_instance_warmup = 120

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.cpu_target
  }
}
