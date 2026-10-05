# ------------------------------------------------------------------
# Customer-managed KMS key: encrypts the database storage, its
# backups, and the Secrets Manager secret holding its password.
# Owning the key means access to the data can be controlled and
# audited separately, and revoked by disabling the key.
# ------------------------------------------------------------------
resource "aws_kms_key" "db" {
  description             = "${var.name} database encryption"
  enable_key_rotation     = true # new key material every year
  deletion_window_in_days = 7    # shortest allowed; keeps lab cleanup quick
}

resource "aws_kms_alias" "db" {
  name          = "alias/${var.name}-db"
  target_key_id = aws_kms_key.db.key_id
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db"
  subnet_ids = var.db_subnet_ids
  tags       = { Name = "${var.name}-db" }
}

# Only the app servers can reach PostgreSQL. No IP ranges at all.
resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "PostgreSQL from the app tier only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-db" }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from app servers only"
  referenced_security_group_id = var.app_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name}-db"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.db_name
  username = var.username

  # RDS generates the password, stores it in Secrets Manager encrypted
  # with our key, and rotates it automatically. Nobody ever sees or
  # types it, and it never appears in Terraform code or state.
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.db.arn

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true
  kms_key_id        = aws_kms_key.db.arn

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period    = 7
  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true

  # Lab settings: easy teardown. Production flips all three.
  deletion_protection = false
  skip_final_snapshot = true
  apply_immediately   = true
}
