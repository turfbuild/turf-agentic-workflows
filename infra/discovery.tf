# Publishes the fleet's URLs to Vault, one secret per environment, so other
# services can discover the functions without reading this configuration's state.
resource "vault_kv_secret_v2" "urls" {
  mount = "secret"
  name  = "turf-hello/${var.environment}"
  data_json = jsonencode({
    greeting = var.greeting
    urls     = aws_lambda_function_url.hello[*].function_url
  })
}
