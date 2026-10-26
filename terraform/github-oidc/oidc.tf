# AWS IAMは、信頼済みルートCAを使ってGitHub OIDCのTLS証明書を検証します。
# thumbprint_listを省略するとAWS IAMが必要な証明書情報を取得するため、
# 変更される可能性があるThumbprintをTerraformコードへ固定しません。
# CA：Certificate Authority、認証局
# ルートCA：信頼関係の最上位にある認証局
# 中間CA：ルートCAから信頼され、実際のWebサイト証明書を発行する認証局

# OIDCプロバイダー定義
resource "aws_iam_openid_connect_provider" "github" {
  # 同ディレクトリ上のdata.tfファイルで定義したGithub OIDC URLを使用する。
  url = local.github_oidc_url

  # AWS STS向けのトークンだけを許可する。
  client_id_list = [
    "sts.amazonaws.com"
  ]
}

###　理解用メモ　###
# 追記➀
# OIDCの目的説明
#※OIDCの目的として、以下をGH　ActionsからAWS CLIを実行する際に、AWS側が判断する必要がある。
#➀このGitHub Actionsは誰なのか？
#➁AWSへのアクセスを許可してよいのか？
#➂何のAWS操作を許可するのか？

# 追記➁
#　OIDCの処理フロー文字起こし
#
#GitHub Actionsが起動
#  ↓
#GitHubが「この処理はKawaiiIRi/gh-oidcから実行された」と証明する短期トークンを発行
#  ↓
#AWSへトークンを提示
#  ↓
#AWSがトークンと条件を検証
#  ↓
#AWSが15分間だけ使用できる一時認証情報を発行
#  ↓
#GitHub ActionsがAWS CLIを実行
#  ↓
#有効期限が切れて認証情報が使えなくなる