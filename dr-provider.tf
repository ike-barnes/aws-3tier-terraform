# Second AWS provider for the disaster-recovery region. us-west-2 is
# one of the two regions the organization's SCP allows.
provider "aws" {
  alias   = "dr"
  region  = "us-west-2"
  profile = "dev"

  default_tags {
    tags = {
      Project     = "aws-3tier-terraform"
      Environment = "dev"
      ManagedBy   = "terraform"
      Owner       = "ike-barnes"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
