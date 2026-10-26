# terraformへ入力できる値とその形式について定義するファイル
variable "aws_region" {
  description = "AWS region in which the Terraform state resources are created."
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID allowed for this configuration. This prevents applying to an unintended account."
  type        = string

  # 入力値の検証ルールの定義
  # この指定されたリソース（ＡＷＳアカウント）が0~9の12桁であればtrue
  #　設定としては過剰気味だが検証目的も兼ねて
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

# tfstate格納先Ｓ３バケットの変数
variable "state_bucket_name" {
  description = "Globally unique S3 bucket name used to store Terraform state."
  type        = string

  # 小文字、数字、.、-を中心としたS3バケット名形式として確認する検証処理
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket_name))
    error_message = "state_bucket_name must be a valid S3 bucket name."
  }
}

# ＫＭＳキーの削除前までの待機日数を定義
# ※ＫＭＳキーは、たとえこれを terraform destroy しても即時削除はされずに「削除予定状態」となる。
variable "kms_deletion_window_in_days" {
  description = "Waiting period before AWS KMS permanently deletes the state encryption key."
  # 待機日数は数字型でのみ受け付け
  type = number
  # 断りが無ければ7日待機後に削除する。
  default = 7

  # この削除までの日数（kms_deletion_window_in_days）リソースについて、7 <= kms_deletion_window_in_days <= 30 の範囲であるかを確認する。
  validation {
    condition     = var.kms_deletion_window_in_days >= 7 && var.kms_deletion_window_in_days <= 30
    error_message = "kms_deletion_window_in_days must be between 7 and 30."
  }
}

# タグの処理は以下順序で行われる
# terraform.tfvars
#   ↓
# var.additional_tags
#   ↓
# merge関数で固定タグと結合
#   ↓
# providerのdefault_tagsに設定
#   ↓
# タグ対応AWSリソースへ自動的に付与
variable "additional_tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
