variable "repository" {
  description = "The demo repository, as owner/name. Its GitHub Environments and variables are managed here; the repository itself is not."
  type        = string
  default     = "turfbuild/turf-agentic-workflows"
}

variable "aws_region" {
  description = "AWS region for the state bucket and the fleets."
  type        = string
  default     = "us-west-2"
}

variable "state_bucket" {
  description = "Name of the S3 bucket that holds every environment's state. Empty picks turf-agentic-workflows-state-<account id>."
  type        = string
  default     = ""
}

variable "create_oidc_provider" {
  description = "Create the GitHub Actions OIDC provider in this account. Set false when token.actions.githubusercontent.com already exists; it is then referenced by its well-known ARN."
  type        = bool
  default     = true
}

variable "environments" {
  description = "One GitHub Environment per key: what its fleet looks like, which approval rule in policy/approval.md governs it, and which branches may deploy to it (\"*\" for any)."
  type = map(object({
    fleet_size      = number
    greeting        = string
    name_prefix     = string
    approval_policy = string
    branches        = string
  }))
  default = {
    staging = {
      fleet_size      = 2
      greeting        = "Hello from staging!"
      name_prefix     = "turf-hello-staging"
      approval_policy = "staging"
      branches        = "*"
    }
    production = {
      fleet_size      = 3
      greeting        = "Hello from production!"
      name_prefix     = "turf-hello-prod"
      approval_policy = "production"
      branches        = "main"
    }
  }
}
