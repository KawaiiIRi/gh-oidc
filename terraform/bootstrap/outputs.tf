# terraform aooly時にターミナル上へ作成リソースを表示するやつら
output "state_bucket_name" {
  description = "S3 bucket that stores Terraform state."
  value       = aws_s3_bucket.terraform_state.id
}

output "state_kms_key_arn" {
  description = "KMS key ARN used to encrypt Terraform state."
  value       = aws_kms_key.terraform_state.arn
}

output "state_kms_alias_arn" {
  description = "KMS alias ARN for the Terraform state key."
  value       = aws_kms_alias.terraform_state.arn
}
