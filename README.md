# gh-oidc

GitHub ActionsからAWSへ、長期アクセスキーを保存せずにOIDCで一時認証する学習用リポジトリです。

## 全体構成

```text
GitHub Actions
  ↓ OIDCトークン
AWS IAM OIDC Provider
  ↓ aud・subを検証
AWS STS AssumeRoleWithWebIdentity
  ↓ 有効期限付きの一時認証情報
GitHub Actions上のAWS CLI
  ↓
sts:GetCallerIdentity / iam:ListUsers
```

Terraform stateは、SSE-KMSで暗号化した専用S3バケットへ保存します。stateロックにはS3ネイティブのロックファイルを使用します。

## ディレクトリ

```text
.
├── .github/workflows/openid-connect.yml
└── terraform
    ├── bootstrap
    │   └── state用S3バケット・KMSキー
    └── github-oidc
        └── OIDC Provider・IAMロール・IAMポリシー
```

## 処理とコードの対応

| 処理 | 対応するファイル・コード |
| --- | --- |
| 手動でワークフローを起動 | `.github/workflows/openid-connect.yml`の`workflow_dispatch` |
| GitHubがOIDCトークンを発行 | 同ファイルの`permissions.id-token: write` |
| AWS認証Actionを呼び出す | 同ファイルの`aws-actions/configure-aws-credentials` |
| 引き受けるIAMロールを指定 | 同ファイルの`role-to-assume` |
| GitHubをOIDC Providerとして登録 | `terraform/github-oidc/oidc.tf` |
| `aud`と`sub`を検証 | `terraform/github-oidc/iam.tf`の信頼ポリシー |
| STSから一時認証情報を取得 | `configure-aws-credentials`が内部で`AssumeRoleWithWebIdentity`を実行 |
| 認証した主体を確認 | `aws sts get-caller-identity` |
| 許可した操作を確認 | `aws iam list-users` |
| `iam:ListUsers`を許可 | `terraform/github-oidc/iam.tf`のカスタムIAMポリシー |

## 事前条件

- Terraform `1.13.4`
- AWS CLIで構築対象のAWSアカウントへ認証済み
- GitHub CLIで`KawaiiIRi/gh-oidc`へ認証済み
- AWSリージョンは`ap-northeast-1`

AWSアクセスキー、シークレットアクセスキー、GitHub TokenはTerraformファイルへ記載しません。

## 1. state用S3・KMSを作成

最初は保存先S3バケットが存在しないため、bootstrapだけローカルstateで開始します。

```bash
cd terraform/bootstrap

cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars`へ、構築対象のAWSリージョン、12桁のAWSアカウントID、作成するstate用S3バケット名を入力します。S3バケット名はAWS全体で一意にする必要があります。

```bash
terraform init
terraform fmt -check
terraform validate
terraform plan -out bootstrap.tfplan
terraform apply bootstrap.tfplan
```

作成された値を確認します。

```bash
terraform output
terraform output -raw state_bucket_name
terraform output -raw state_kms_key_arn
```

## 2. bootstrapのstateをS3へ移行

`backend.tf.example`と`backend.hcl.example`をローカル用ファイルへコピーします。`backend.hcl`の`<STATE_BUCKET_NAME>`には`terraform output -raw state_bucket_name`、`<STATE_KMS_KEY_ARN>`には`terraform output -raw state_kms_key_arn`の結果を入力します。`region`はバケットを作成したリージョンと一致させます。

```bash
cp backend.tf.example backend.tf
cp backend.hcl.example backend.hcl
```

置換後、ローカルstateをS3へ移行します。

```bash
terraform init -migrate-state -backend-config=backend.hcl
terraform state list
```

移行確認後も、ローカルの旧stateバックアップはGitへ追加しません。

## 3. GitHub OIDC・IAMを作成

`bootstrap`で取得したKMSキーARNを、`terraform/github-oidc/backend.hcl`にも設定します。

```bash
cd ../github-oidc

cp terraform.tfvars.example terraform.tfvars
cp backend.hcl.example backend.hcl
```

`terraform.tfvars`へAWSリージョン、AWSアカウントID、許可するGitHubリポジトリ、GitHub所有者ID、GitHubリポジトリID、許可ブランチ、IAMロール名を入力します。GitHubの2つのIDは任意の値ではなく、対象リポジトリの情報から取得した値を使います。

```bash
gh api --method GET repos/KawaiiIRi/gh-oidc --jq '.owner.id'
gh api --method GET repos/KawaiiIRi/gh-oidc --jq '.id'
gh api --method GET repos/KawaiiIRi/gh-oidc/actions/oidc/customization/sub
```

最初の結果を`github_owner_id`、2番目の結果を`github_repository_id`へ文字列として入力します。この構成は`use_default: true`かつ`use_immutable_subject: true`のリポジトリを対象とし、次の形式の`sub`と指定ブランチを完全一致で照合します。

```text
repo:<GITHUB_OWNER>@<GITHUB_OWNER_ID>/<GITHUB_REPOSITORY>@<GITHUB_REPOSITORY_ID>:ref:refs/heads/<GITHUB_BRANCH>
```

カスタムsubjectや旧形式を使うリポジトリ、GitHub Environmentを指定するジョブでは`sub`の形式が異なるため、信頼条件も合わせて変更する必要があります。[GitHub OIDCの仕様](https://docs.github.com/en/actions/reference/security/oidc#immutable-subject-claims)

`backend.hcl`の`<STATE_BUCKET_NAME>`と`<STATE_KMS_KEY_ARN>`をbootstrapの出力値に置き換え、`region`をバケットのリージョンと一致させてから初期化します。`backend.hcl`はTerraform変数の評価前に読み込まれるため、`terraform.tfvars`ではなく手動設定します。

```bash
terraform init -backend-config=backend.hcl
terraform fmt -check
terraform validate
terraform plan -out github-oidc.tfplan
terraform apply github-oidc.tfplan
```

作成されたロールARNを確認します。

```bash
terraform output -raw github_actions_role_arn
```

## 4. AWSアカウントIDとIAMロールARNをGitHubへ登録

AWSアカウントIDとIAMロールARNは秘密情報ではありませんが、実環境識別子をWorkflowへ直接記載しないため、GitHub Actions Variableとして登録します。

Web画面では、対象リポジトリの`Settings → Secrets and variables → Actions → Variables → New repository variable`から`AWS_ACCOUNT_ID`と`AWS_ROLE_ARN`を登録できます。以下のCLIコマンドでも同じRepository Variablesへ登録できます。

このWorkflowはGitHub Environmentを指定しないため、Environment Variablesには登録しません。Environment Variablesは、そのEnvironmentを`jobs.<job_id>.environment`で指定したジョブだけが使用します。[GitHubの変数設定](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-variables)

```bash
gh variable set AWS_ACCOUNT_ID \
  --repo KawaiiIRi/gh-oidc \
  --body "$(terraform output -raw aws_account_id)"

gh variable set AWS_ROLE_ARN \
  --repo KawaiiIRi/gh-oidc \
  --body "$(terraform output -raw github_actions_role_arn)"
```

登録確認：

```bash
gh variable list --repo KawaiiIRi/gh-oidc
```

以前登録した`AWS_ID`や`ROLE_NAME`のSecretは、このワークフローでは使用しません。

## 5. ワークフローを実行

Terraformの変更をAWSへ適用し、Repository Variablesを登録し、`.github/workflows/openid-connect.yml`をデフォルトブランチへ反映した後、手動実行します。ローカルファイルの修正やGitへのcommitだけではAWSのIAM信頼条件は更新されません。設定を変更した場合は以前保存したplanを再利用せず、最新の構成からplanを作成して確認します。

```bash
gh workflow run openid-connect.yml \
  --repo KawaiiIRi/gh-oidc \
  --ref main
```

実行状況を確認します。

```bash
gh run list \
  --repo KawaiiIRi/gh-oidc \
  --workflow openid-connect.yml \
  --limit 5
```

ワークフローは以下を確認し、成功すれば終了します。

1. GitHub OIDCを使用してIAMロールを引き受けられること
2. 一時認証情報で`aws sts get-caller-identity`を実行できること（識別情報はログへ出力しません）
3. 最小権限として許可した`aws iam list-users`を実行できること（ユーザー一覧はログへ出力しません）

## セキュリティ上の判断

- OIDC Providerの`thumbprint_list`は、GitHub OIDCをAWSの信頼済みルートCAで検証するため省略しています。
- IAMロールの信頼範囲は、`terraform.tfvars`で指定したGitHub所有者ID・リポジトリID・名前とブランチだけに制限します。
- IAM権限は`iam:ListUsers`だけです。
- 変更系の`iam:CreateUser`は許可せず、ワークフローからも実行しません。
- state用S3バケットはPublic Access Block、バージョニング、SSE-KMS、TLS強制を設定しています。
- `prevent_destroy`は学習環境のため無効です。本番ではTerraformコード内のコメントアウトを解除します。

## 削除時の注意

state用S3バケットは`force_destroy = false`であり、バージョニングされたstateが残っている間は削除できません。bootstrapを削除する場合は、先にstateを安全な場所へ移行し、S3内の全バージョンと削除マーカーを確認してから作業します。
