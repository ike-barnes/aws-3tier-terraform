# The root module only wires modules together. Each layer lives in
# its own reusable module under modules/.

module "vpc" {
  source = "./modules/vpc"

  name     = var.name
  cidr     = var.vpc_cidr
  az_count = 2
}

module "web" {
  source = "./modules/web"

  name              = var.name
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  app_subnet_ids    = module.vpc.app_subnet_ids

  instance_type    = "t4g.micro" # Graviton (ARM)
  architecture     = "arm64"
  min_size         = 2
  max_size         = 4
  desired_capacity = 2

  golden_ami_name_prefix = "three-tier-golden-"
}

module "database" {
  source = "./modules/database"

  name                  = var.name
  vpc_id                = module.vpc.vpc_id
  db_subnet_ids         = module.vpc.db_subnet_ids
  app_security_group_id = module.web.app_security_group_id
  instance_class        = "db.t4g.small"
}

# The app servers may read the database secret, and decrypt it with
# the database key. Nothing else.
resource "aws_iam_role_policy" "app_read_db_secret" {
  name = "read-db-secret"
  role = module.web.app_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadDatabaseSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = module.database.secret_arn
      },
      {
        Sid      = "DecryptWithDatabaseKey"
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = module.database.kms_key_arn
      }
    ]
  })
}
