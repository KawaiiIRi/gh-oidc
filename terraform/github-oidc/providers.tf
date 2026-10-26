# プロバイダー定義
provider "aws" {
  # 構築時に使用するリージョン
  region = var.aws_region
  # 構築時に使用するAWSアカウントを指定
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = merge(
      {
        Project   = "gh-oidc"
        ManagedBy = "Terraform"
        Component = "github-oidc"
      },
      var.additional_tags
    )
  }
}
