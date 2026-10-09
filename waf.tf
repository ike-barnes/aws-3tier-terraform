# ------------------------------------------------------------------
# AWS WAF in front of the load balancer. Requests are inspected
# before they reach the app servers; anything matching a rule is
# blocked at the edge with a 403.
# ------------------------------------------------------------------
data "aws_lb" "app" {
  name       = "${var.name}-alb"
  depends_on = [module.web]
}

locals {
  # AWS-managed rule groups, maintained and updated by AWS.
  waf_managed_rules = [
    { name = "AWSManagedRulesAmazonIpReputationList", priority = 0 }, # known malicious IPs and bots
    { name = "AWSManagedRulesCommonRuleSet", priority = 2 },          # OWASP-style: XSS, bad paths, oversize payloads
    { name = "AWSManagedRulesKnownBadInputsRuleSet", priority = 3 },  # exploit patterns, e.g. Log4j
    { name = "AWSManagedRulesSQLiRuleSet", priority = 4 },            # SQL injection, relevant with a database tier
  ]
}

resource "aws_wafv2_web_acl" "app" {
  name        = "${var.name}-waf"
  description = "Edge protection for the ${var.name} load balancer"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = local.waf_managed_rules
    content {
      name     = rule.value.name
      priority = rule.value.priority

      override_action {
        none {} # enforce the group's own block actions
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.value.name
        sampled_requests_enabled   = true
      }
    }
  }

  # Rate limiting: one IP sending more than 100 requests in a minute
  # is blocked until its rate drops. Low on purpose so it can be
  # demonstrated; a production limit would be based on real traffic.
  rule {
    name     = "rate-limit-per-ip"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit                 = 100
        evaluation_window_sec = 60
        aggregate_key_type    = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit-per-ip"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-waf"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "app" {
  resource_arn = data.aws_lb.app.arn
  web_acl_arn  = aws_wafv2_web_acl.app.arn
}

# ---------------- WAF logging ----------------
# WAF requires the log group name to start with "aws-waf-logs-".
resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-${var.name}"
  retention_in_days = 30
}

data "aws_iam_policy_document" "waf_logs" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.waf.arn}:*"]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "waf" {
  policy_name     = "${var.name}-waf-logs"
  policy_document = data.aws_iam_policy_document.waf_logs.json
}

resource "aws_wafv2_web_acl_logging_configuration" "app" {
  resource_arn            = aws_wafv2_web_acl.app.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]

  depends_on = [aws_cloudwatch_log_resource_policy.waf]
}

output "waf_web_acl_name" {
  value = aws_wafv2_web_acl.app.name
}

output "waf_log_group" {
  value = aws_cloudwatch_log_group.waf.name
}
