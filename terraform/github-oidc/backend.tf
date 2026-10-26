# terraform自体の設定ブロック
terraform {
  # このディレクトリのtfファイルによる構築物について、stateファイルの格納先をS3にしますという宣言
  # 空にしているのは、バケット名やKMSキーをbackend.hclファイルから取得するため
  backend "s3" {}
}
