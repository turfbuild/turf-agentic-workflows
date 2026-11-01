# A fleet of identical AWS Lambda functions behind one shared execution role,
# each reachable at a public function URL so the agent can verify a rollout by
# calling it. Adapted from turf-examples/terraform/aws/lambda-fleet.
#
# The point is the SECOND run: changing var.greeting rewrites an environment
# variable on every function, so a re-plan is N update-in-place changes and the
# verify step proves the new value reached the running code.

# The deployment package, built from source at plan time. The zip lands next to
# this configuration (git-ignored) and is regenerated whenever hello-world/
# changes, so source_code_hash moves with the source and the fleet re-deploys.
data "archive_file" "hello" {
  type        = "zip"
  source_dir  = "${path.module}/hello-world"
  output_path = "${path.module}/hello-world.zip"
}

# One role shared by the whole fleet. Lambda needs only permission to write its
# own logs, which is exactly what AWSLambdaBasicExecutionRole grants.
resource "aws_iam_role" "lambda_exec" {
  name = "${var.name_prefix}-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Renamed from aws_iam_role_policy_attachment.lambda_policy, for the policy it attaches. The
# moved block carries the state over, so the plan is a move, not a replacement.
moved {
  from = aws_iam_role_policy_attachment.lambda_policy
  to   = aws_iam_role_policy_attachment.basic_execution
}

resource "aws_lambda_function" "hello" {
  count = var.fleet_size

  function_name = "${var.name_prefix}-${count.index}"
  role          = aws_iam_role.lambda_exec.arn

  filename         = data.archive_file.hello.output_path
  source_code_hash = data.archive_file.hello.output_base64sha256

  runtime = var.runtime
  handler = "hello.handler"

  # The handler reads its greeting from the environment rather than a literal,
  # which is what makes a patch observable: invoking a function proves the new
  # value reached the running code, not merely the state file.
  environment {
    variables = {
      GREETING    = var.greeting
      ENVIRONMENT = var.environment
    }
  }
}

# A public URL per function. The demo wants the agent to GET each one from the
# workflow sandbox, so no IAM auth; the permission below is what AWS requires
# before an unauthenticated URL answers.
resource "aws_lambda_function_url" "public" {
  count = var.fleet_size

  function_name      = aws_lambda_function.hello[count.index].function_name
  authorization_type = "NONE"
}

# Renamed from aws_lambda_function_url.hello: it is the public URL, so say so. The moved
# block carries the state over, so the plan is a move, not a replacement.
moved {
  from = aws_lambda_function_url.hello
  to   = aws_lambda_function_url.public
}

resource "aws_lambda_permission" "public" {
  count = var.fleet_size

  statement_id           = "AllowPublicFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.hello[count.index].function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

# Renamed from aws_lambda_permission.public_url, to match the URL resource it permits. The
# moved block carries the state over, so the plan is a move, not a replacement.
moved {
  from = aws_lambda_permission.public_url
  to   = aws_lambda_permission.public
}

# The release marker. Its input changes whenever the greeting, the environment,
# the fleet's URLs or the function code change, so the verify action in
# rollout.turf.hcl runs after the first create and after every patch, once for
# the whole fleet, with the real URLs.
resource "terraform_data" "rollout" {
  input = {
    greeting    = var.greeting
    environment = var.environment
    urls        = aws_lambda_function_url.public[*].function_url
    code        = data.archive_file.hello.output_base64sha256
  }

  depends_on = [aws_lambda_permission.public]
}

# Renamed from terraform_data.release, for the rollout it marks (rollout.turf.hcl verifies it).
# The moved block carries the state over, so the plan is a move, not a replacement.
moved {
  from = terraform_data.release
  to   = terraform_data.rollout
}
