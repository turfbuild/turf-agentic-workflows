terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.17"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "5.4.0"
    }
  }

  # A partial backend: the bucket, key and region differ per environment, so the
  # workflow passes them to open({ backend_config }) from its run context. The
  # lock file is the state object's ".tflock" sibling, no DynamoDB table.
  backend "s3" {
    use_lockfile = true
  }
}

# Every AWS resource of the fleet carries these tags, so one environment's
# functions and role can be found, filtered and costed together.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "turf-agentic-workflows"
      Component   = "fleet"
      Environment = var.environment
      Repository  = "turfbuild/turf-agentic-workflows"
      ManagedBy   = "turf"
    }
  }
}

# Vault's address and token come from VAULT_ADDR and VAULT_TOKEN in the
# environment.
provider "vault" {}
