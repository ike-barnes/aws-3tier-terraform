terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # State lives in the shared state bucket (management account), under
  # its own key. The backend signs in with the mgmt SSO profile, while
  # the resources below are built in the dev account.
  backend "s3" {
    bucket       = "ikebarnes-tfstate-481503225728"
    key          = "aws-3tier-terraform/dev/terraform.tfstate"
    region       = "us-east-1"
    profile      = "mgmt"
    encrypt      = true
    use_lockfile = true
  }
}
