provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    # ➀固定タグと➁追加タグをマッピングする
    tags = merge(
      # ➀固定タグ（Terraform構成で原則として常に付与するタグ）
      {
        Project = "gh-oidc"
        # terraformが管理リソースであること
        ManagedBy = "Terraform"
        #　stateが保存基盤であること
        Component = "terraform-backend"
      },
      # ➁追加タグ
      # ※terraform.tfvarsで指定した追加タグを結合する。
      var.additional_tags
    )
  }
}
