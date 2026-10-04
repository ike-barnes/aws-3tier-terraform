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

  instance_type    = "t3.micro"
  min_size         = 2
  max_size         = 4
  desired_capacity = 2
}
