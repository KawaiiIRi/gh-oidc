# 実行terraformのバージョン指定
# 主にuse_lockfile = true が使用可能なバージョンであればOK
terraform {
  required_version = ">= 1.13.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
