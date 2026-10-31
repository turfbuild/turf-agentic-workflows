# Both providers read their credentials from the engine's environment: the AWS
# session (`aws login`, or AWS_PROFILE) and GITHUB_TOKEN (`gh auth token`, which
# needs the repo and workflow scopes to manage environments and variables).
# Every AWS resource of this configuration carries these tags; the CI roles add
# their Environment. infra/ tags the fleet the same way, with Component = "fleet".
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project    = "turf-agentic-workflows"
      Component  = "setup"
      Repository = var.repository
      ManagedBy  = "turf"
    }
  }
}

provider "github" {
  owner = local.owner
}
