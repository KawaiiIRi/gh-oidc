# 現在のAWSパーティション取得（通常は「aws」）
data "aws_partition" "current" {}

# KMSキーポリシーのJSONをtfファイル内で作成するリソース
# この設定により、アカウント内のIAMポリシーを通じてKMSキー権限を管理できるようになる。
data "aws_iam_policy_document" "terraform_state_kms" {
  # ポリシーの許可ルール定義
  statement {
    # statement名を命名
    sid = "EnableAccountPermissions"
    # 後述のprincipalという対象についてのみ「許可します。」の宣言
    effect = "Allow"

    # 許可対象定義
    principals {
      #　AWSアカウントやIAM Principalが対象
      type = "AWS"
      # 対象のAWSアカウントの root Principalを指定する。
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${var.aws_account_id}:root"]
    }

    # このKMSキーに対するKMS操作を、アカウントのIAM権限経由で管理可能にする。
    actions = ["kms:*"]
    # KMSキーポリシーでは、このポリシーが付くKMSキー自身を表す。（無論、Principalの対象はvariablesで定義した、対象のAWSアカウント）
    resources = ["*"]
  }
}

# stateファイル暗号化用のKMSキー作成・定義
resource "aws_kms_key" "terraform_state" {
  description = "Encrypts Terraform state for the gh-oidc project"
  # 自動キーローテーションを有効に設定
  enable_key_rotation = true
  # 自動キーローテーションにおいて、削除待期期間を下記変数から取得する。
  deletion_window_in_days = var.kms_deletion_window_in_days
  # KMSキーポリシーを下記JSONから取得する。
  policy = data.aws_iam_policy_document.terraform_state_kms.json

  #学習環境では削除できるように無効化しています。（何回も作っては壊して検証したいので）
  #本番環境では誤削除防止のためコメントアウトを解除してください。
  # lifecycle {
  #   prevent_destroy = true
  # }
}

# KMSキーのエイリアス定義
resource "aws_kms_alias" "terraform_state" {
  # AWS上で表示されるエイリアス
  name = "alias/terraform-state-gh-oidc"
  # このエイリアスで使用するKMSキー
  target_key_id = aws_kms_key.terraform_state.key_id
}

# state格納用S3バケット構築
resource "aws_s3_bucket" "terraform_state" {
  # バケット名を変数から取得
  bucket = var.state_bucket_name
  # オブジェクトが残っているバケットの強制削除しない
  force_destroy = false

  # 学習環境では削除できるように無効化しています。
  # 本番環境では、誤削除防止のためコメントアウトを解除してください。
  # lifecycle {
  #   prevent_destroy = true
  # }
}

# S３オブジェクト所有権の設定を定義
# ※バケット所有者（構築先AWSアカウントID）であればなんでも操作が出来るわけでは無く、
# アクセスの可否はIAM・バケット・KMS・VPC Endpoint・SCPなどのポリシーで管理される。
resource "aws_s3_bucket_ownership_controls" "terraform_state" {
  # 対象バケット
  bucket = aws_s3_bucket.terraform_state.id

  # ACL無効化、かつバケット所有者による一元管理（アクセスの制御をIAM・バケットポリシーなどに統一する。）
  # (別AWSからオブジェクトを送信されても、その送信先S3の所有者(※構築AWSアカウント)がオブジェクトを自由に送られたオブジェクトを所有、故に操作可能)
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# S3の公開防止（パブリックアクセスブロックについて）設定定義
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  # 対象バケット
  bucket = aws_s3_bucket.terraform_state.id

  # 新しい公開ACL設定を拒否
  block_public_acls = true
  # 公開アクセスを許可するバケットポリシーを拒否
  block_public_policy = true
  # 既存の公開ACLがあっても無視する
  ignore_public_acls = true
  # 公開扱いのポリシーによるアクセスを制限する
  restrict_public_buckets = true
}

# S3バケットのバージョニング設定
resource "aws_s3_bucket_versioning" "terraform_state" {
  # 対象バケット
  bucket = aws_s3_bucket.terraform_state.id

  # バージョニングを有効に設定
  versioning_configuration {
    status = "Enabled"
  }
}

# S3のデフォルト暗号化設定
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  # 対象バケット
  bucket = aws_s3_bucket.terraform_state.id

  # 暗号化ルールの定義
  rule {
    # バケットの暗号化を有効
    bucket_key_enabled = true

    # 暗号化に用いるキーを指定
    apply_server_side_encryption_by_default {
      # KMSキーを用いて暗号化する
      kms_master_key_id = aws_kms_key.terraform_state.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# S3バケットポリシー
# [設定内容]
# 1.HTTPSではないアクセスを拒否
# 2.暗号化ヘッダーのないアップロードを拒否
# 3.SSE-KMS以外の暗号化を拒否
# 4.KMSキーIDのないアップロードを拒否
# 5.指定KMSキー以外を使用したアップロードを拒否
data "aws_iam_policy_document" "terraform_state_bucket" {
  # 一つ目の拒否ルール定義
  # 例：PutObjectが許可されていても、HTTPS通信ならばバケットポリシーのDenyで拒否される。
  statement {
    sid = "DenyInsecureTransport"
    # ポリシーは条件に一致する場合に対象を 拒否 する設定
    effect = "Deny"

    principals {
      # 全てのアクセス元を拒否判定の対象にする
      type        = "*"
      identifiers = ["*"]
    }

    # S3が実行する全ての操作を判定（拒否）対象にする
    actions = ["s3:*"]
    # 対象のS3バケットおよびそのオブジェクトをこのポリシーによる判定対象にする
    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*"
    ]

    # 拒否条件の定義
    condition {
      # 真偽値で条件判定する
      test = "Bool"
      # 条件判定において、対象のプロトコル（TLS/HTTPS）による通信であるかを確認
      variable = "aws:SecureTransport"
      # HTTPSで無い場合に条件成立とする
      values = ["false"]
    }
  }

  # 二つ目の拒否ルール定義（アップロード要求自体にも暗号化をしていないものへの拒否設定）
  statement {
    sid    = "DenyUploadsWithoutEncryptionHeader"
    effect = "Deny"
    # 全てのアクセス元を拒否対象とする
    principals {
      type        = "*"
      identifiers = ["*"]
    }

    # S3へのPutObjectのみを拒否する
    actions = ["s3:PutObject"]
    # 対象のバケット内の全てのオブジェクトを対象とする。
    resources = ["${aws_s3_bucket.terraform_state.arn}/*"]

    # ヘッダーの有無を確認する
    condition {
      test     = "Null"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["true"]
    }
  }

  # 三つ目の拒否ルール定義（暗号化方式がKMSでないなら拒否）
  statement {
    sid    = "DenyUploadsUsingIncorrectEncryption"
    effect = "Deny"
    # 対象は全てのアクセス元を拒否する
    principals {
      type        = "*"
      identifiers = ["*"]
    }

    # 制限対象は対象のS3バケット内オブジェクトにおいて、PutObjectのみ
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.terraform_state.arn}/*"]

    # 制限する際の条件定義
    # 暗号化方式がKMSで無い場合拒否する。（例：SSE-S3、AES256は無理）
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }

  # 四つ目の拒否ルール定義（KMSキーIDが設定されていなければ拒否）
  statement {
    sid    = "DenyUploadsWithoutKmsKeyId"
    effect = "Deny"

    # 全てのアクセス元を拒否対象とする
    principals {
      type        = "*"
      identifiers = ["*"]
    }

    # 制限対象は対象のS3バケット内オブジェクトにおいて、PutObjectのみ
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.terraform_state.arn}/*"]

    # 制限条件定義
    # KMSキーIDが設定されているかを確認する。
    condition {
      test     = "Null"
      variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
      values   = ["true"]
    }
  }

  # 五つ目の拒否ルールを定義（aws_kms_key.terraform_state のKMSキーでないものを拒否する）
  statement {
    sid    = "DenyUploadsUsingIncorrectKmsKey"
    effect = "Deny"

    # 全てのアクセス元を拒否対象とする
    principals {
      type        = "*"
      identifiers = ["*"]
    }

    # 制限対象は対象のS3バケット内オブジェクトにおいて、PutObject権限のみ
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.terraform_state.arn}/*"]

    # 制限条件定義
    # 暗号化に用いるKMSキーが「aws_kms_key.terraform_state」のものでないなら拒否
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
      # このKMSで無いなら拒否するということ
      values = [aws_kms_key.terraform_state.arn]
    }
  }
}

# 上記で生成したバケットポリシーをS3バケットへ設定する
resource "aws_s3_bucket_policy" "terraform_state" {
  # 対象のS3バケット
  bucket = aws_s3_bucket.terraform_state.id
  # 使用するS3バケットポリシー
  policy = data.aws_iam_policy_document.terraform_state_bucket.json

  # 依存関係の定義
  depends_on = [
    aws_s3_bucket_ownership_controls.terraform_state,
    aws_s3_bucket_public_access_block.terraform_state,
    aws_s3_bucket_server_side_encryption_configuration.terraform_state
  ]
}
