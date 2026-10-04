provider "aws" {
  region  = var.region
  profile = "dev" # everything is built in the dev account

  default_tags {
    tags = {
      Project     = "aws-3tier-terraform"
      Environment = "dev"
      ManagedBy   = "terraform"
      Owner       = "ike-barnes"
    }
  }
}
