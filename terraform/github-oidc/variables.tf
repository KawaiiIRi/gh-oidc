# 構築先のリージョン
variable "aws_region" {
  description = "AWS region used by the AWS provider and GitHub Actions workflow."
  type        = string
}

# 構築の際などに使用するAWSアカウント
variable "aws_account_id" {
  description = "AWS account ID allowed for this configuration. This prevents applying to an unintended account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

# 使用対象のGithubリポジトリ
variable "github_repository" {
  description = "GitHub repository allowed to assume the IAM role, in OWNER/REPOSITORY format."
  type        = string

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repository))
    error_message = "github_repository must use OWNER/REPOSITORY format."
  }
}

# GitHubの所有者IDとリポジトリIDはimmutable subjectの照合に使用する。
variable "github_owner_id" {
  description = "Immutable numeric ID of the GitHub repository owner."
  type        = string

  validation {
    condition     = can(regex("^[1-9][0-9]*$", var.github_owner_id))
    error_message = "github_owner_id must be a positive numeric GitHub owner ID."
  }
}

variable "github_repository_id" {
  description = "Immutable numeric ID of the GitHub repository."
  type        = string

  validation {
    condition     = can(regex("^[1-9][0-9]*$", var.github_repository_id))
    error_message = "github_repository_id must be a positive numeric GitHub repository ID."
  }
}

# OIDCトークンの発行を許可するGitHubブランチ
variable "github_branch" {
  description = "GitHub branch allowed to assume the IAM role."
  type        = string

  validation {
    condition     = length(trimspace(var.github_branch)) > 0
    error_message = "github_branch must not be empty."
  }
}

# IAMロール名
variable "github_actions_role_name" {
  description = "Name of the IAM role assumed by GitHub Actions."
  type        = string
  default     = "github-actions"
}

variable "additional_tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
