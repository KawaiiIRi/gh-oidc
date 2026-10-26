# GitHubのimmutable subject形式に合わせ、所有者・リポジトリの名前とIDを含める。
locals {
  github_oidc_subject = format(
    "repo:%s@%s/%s@%s:ref:refs/heads/%s",
    split("/", var.github_repository)[0],
    var.github_owner_id,
    split("/", var.github_repository)[1],
    var.github_repository_id,
    var.github_branch
  )
}

# IAMロールの信頼ポリシーJSONを"Terraformで組み立てます"。
data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    sid     = "AllowGitHubActionsToAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # aud（Audience）は、このOIDCトークンがAWS STS向けに発行されたことを確認します。
    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # sub（Subject）は、所有者ID・リポジトリIDを含め、指定ブランチと完全一致させる。
    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:sub"
      values   = [local.github_oidc_subject]
    }
  }
}

# 権限ポリシー
resource "aws_iam_role" "github_actions" {
  name                 = var.github_actions_role_name
  description          = "Assumed by GitHub Actions in ${var.github_repository} through OIDC"
  assume_role_policy   = data.aws_iam_policy_document.github_actions_assume_role.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "list_iam_users" {
  statement {
    sid       = "ListIamUsers"
    effect    = "Allow"
    actions   = ["iam:ListUsers"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "list_iam_users" {
  name        = "${var.github_actions_role_name}-list-users"
  description = "Allows the GitHub Actions OIDC test workflow to list IAM users only"
  policy      = data.aws_iam_policy_document.list_iam_users.json
}

resource "aws_iam_role_policy_attachment" "list_iam_users" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.list_iam_users.arn
}
