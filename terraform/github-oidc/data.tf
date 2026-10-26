data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  github_oidc_url  = "https://token.actions.githubusercontent.com"
  github_oidc_host = trimprefix(local.github_oidc_url, "https://")
}
