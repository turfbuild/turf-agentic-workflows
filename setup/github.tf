data "github_repository" "demo" {
  full_name = var.repository
}

# One GitHub Environment per key. Its variables are what the workflows read
# (the role to assume, where the state lives, the fleet's values, which
# approval rule applies), and its deployment branch policy is what decides
# which branches may run a job against it.
resource "github_repository_environment" "env" {
  for_each = var.environments

  repository  = data.github_repository.demo.name
  environment = each.key

  dynamic "deployment_branch_policy" {
    for_each = each.value.branches == "*" ? [] : [each.value.branches]
    content {
      protected_branches     = false
      custom_branch_policies = true
    }
  }
}

resource "github_repository_environment_deployment_policy" "branch" {
  for_each = { for k, v in var.environments : k => v if v.branches != "*" }

  repository     = data.github_repository.demo.name
  environment    = github_repository_environment.env[each.key].environment
  branch_pattern = each.value.branches
}

locals {
  # Every variable of every environment, keyed "<environment>/<name>".
  environment_variables = merge([
    for env, cfg in var.environments : {
      for name, value in {
        AWS_ROLE_ARN         = aws_iam_role.ci[env].arn
        AWS_REGION           = var.aws_region
        TF_STATE_BUCKET      = aws_s3_bucket.state.bucket
        TF_STATE_KEY         = "${env}/lambda-fleet.tfstate"
        TURF_ENVIRONMENT     = env
        TURF_APPROVAL_POLICY = cfg.approval_policy
        TF_VAR_fleet_size    = tostring(cfg.fleet_size)
        TF_VAR_greeting      = cfg.greeting
        TF_VAR_name_prefix   = cfg.name_prefix
        TF_VAR_aws_region    = var.aws_region
        TF_VAR_environment   = env
      } : "${env}/${name}" => { environment = env, name = name, value = value }
    }
  ]...)
}

resource "github_actions_environment_variable" "v" {
  for_each = local.environment_variables

  repository    = data.github_repository.demo.name
  environment   = github_repository_environment.env[each.value.environment].environment
  variable_name = each.value.name
  value         = each.value.value
}
