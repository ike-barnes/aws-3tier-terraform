# ------------------------------------------------------------------
# AWS Backup: daily database backups, copied automatically to a
# second region, each copy encrypted with a key in that region.
# ------------------------------------------------------------------
locals {
  db_arn = "arn:aws:rds:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:db:${var.name}-db"
}

# Customer-managed key for the DR copies in us-west-2. A KMS key only
# works in its own region, so the copy needs one there.
resource "aws_kms_key" "dr" {
  provider                = aws.dr
  description             = "${var.name} disaster-recovery backups"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "dr" {
  provider      = aws.dr
  name          = "alias/${var.name}-dr-backup"
  target_key_id = aws_kms_key.dr.key_id
}

# force_destroy lets the lab tear down cleanly. Production would keep
# the vaults and lock them (see decision 18).
resource "aws_backup_vault" "primary" {
  name          = "${var.name}-vault"
  force_destroy = true
}

resource "aws_backup_vault" "dr" {
  provider      = aws.dr
  name          = "${var.name}-dr-vault"
  kms_key_arn   = aws_kms_key.dr.arn
  force_destroy = true
}

# ---------------- Backup service role ----------------
resource "aws_iam_role" "backup" {
  name = "${var.name}-backup"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# The database and its backups are encrypted with customer-managed
# keys, so the backup role needs to use both of them.
resource "aws_iam_role_policy" "backup_kms" {
  name = "use-data-keys"
  role = aws_iam_role.backup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
        "kms:CreateGrant",
      ]
      Resource = [module.database.kms_key_arn, aws_kms_key.dr.arn]
    }]
  })
}

# ---------------- Plan and selection ----------------
resource "aws_backup_plan" "db" {
  name = "${var.name}-db-backup"

  rule {
    rule_name         = "daily-with-dr-copy"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = "cron(0 5 * * ? *)" # 05:00 UTC daily
    start_window      = 60
    completion_window = 180

    lifecycle {
      delete_after = 7
    }

    copy_action {
      destination_vault_arn = aws_backup_vault.dr.arn
      lifecycle {
        delete_after = 7
      }
    }
  }
}

resource "aws_backup_selection" "db" {
  name         = "${var.name}-db"
  plan_id      = aws_backup_plan.db.id
  iam_role_arn = aws_iam_role.backup.arn
  resources    = [local.db_arn]

  depends_on = [module.database]
}

output "backup_role_name" {
  value = aws_iam_role.backup.name
}

output "backup_vault" {
  value = aws_backup_vault.primary.name
}

output "dr_backup_vault" {
  value = "${aws_backup_vault.dr.name} (us-west-2)"
}

output "db_arn" {
  value = local.db_arn
}
