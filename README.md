# AWS Lightsail shared PostgreSQL infrastructure

Java + Gradle AWS CDK project for one shared Lightsail PostgreSQL database in AWS Ireland.

## Defaults

- Region: `eu-west-1`
- Availability zone: `eu-west-1a`
- Lightsail database resource name: `shared-postgres`
- Bundle: `micro_2_0` (`$15/month`, Standard Micro)
- PostgreSQL blueprint: `postgres_18`
- Public access: `false`
- Master database: `postgres`
- Master user: `postgres_admin`
- Logical app databases: `elfico`, `czyjafakturka`

## Workflows

- `🧰 Bootstrap CDK`: creates/updates the CDK bootstrap resources in `eu-west-1`.
- `🚀 Deploy shared Lightsail database`: deploys the CDK stack.
- `🗄️ Initialize logical databases`: temporarily makes the DB public, creates/updates app DBs and users, stores app credentials in Secrets Manager, then makes the DB private again.
- `🔐 Set database access`: manually toggles public/private access.
- `🔎 Database status`: prints current Lightsail DB status.
- `📸 Create database snapshot`: creates a manual database snapshot.

To run any workflow, open the repository in GitHub, select **Actions**, select the named workflow in the left sidebar, select **Run workflow**, choose the required inputs, and confirm with **Run workflow**.

## Required GitHub Secrets

Create a GitHub environment named `production`.

Add these environment secrets:

- `AWS_ROLE_ARN`: IAM role ARN assumed by GitHub Actions through OIDC.
- `LIGHTSAIL_MASTER_USER_PASSWORD`: initial PostgreSQL master password for `postgres_admin`.

Generate the master password locally:

```bash
openssl rand -base64 48 | tr -d '/@"[:space:]' | cut -c1-48
```

Do not commit this password. The apps must not use the master user.

## Rollout

### 1. Set local variables

```bash
export AWS_REGION=eu-west-1
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export GITHUB_OWNER="tostrowski"
export GITHUB_REPO="aws-lightsail-shared-infra"
```

### 2. Create the GitHub OIDC role

Run the setup script:

```bash
./scripts/create-github-oidc-role.sh
```

The script creates or updates:

- GitHub OIDC provider for `token.actions.githubusercontent.com`
- IAM role `github-lightsail-shared-infra`
- role trust policy for `repo:<github-owner>/aws-lightsail-shared-infra:environment:production`
- inline rollout policy

The initial rollout policy allows:

```text
cloudformation:*
lightsail:*
secretsmanager:*
ssm:GetParameter
sts:AssumeRole
```

The script prints the IAM role ARN to use as the GitHub environment secret `AWS_ROLE_ARN`.

Tighten this policy after the first successful deployment.

This is the one bootstrap dependency that cannot be solved by assuming the same role from GitHub Actions: the role must exist before GitHub can assume it. If you want zero local AWS CLI commands, create this role once in the AWS Console or use temporary AWS access keys in GitHub for a one-time admin setup workflow.

### 3. Configure GitHub

In GitHub:

```text
Repo -> Settings -> Environments -> New environment -> production
```

Recommended: require manual approval for `production`. The database initialization workflow temporarily opens the database publicly.

Add environment secrets:

```text
AWS_ROLE_ARN
LIGHTSAIL_MASTER_USER_PASSWORD
```

### 4. Push the repository

If this folder is not a git repo yet:

```bash
git init
git add .
git commit -m "Create shared Lightsail PostgreSQL CDK infrastructure"
git branch -M main
git remote add origin git@github.com:<github-owner>/aws-lightsail-shared-infra.git
git push -u origin main
```

### 5. Bootstrap CDK

Run the GitHub Actions workflow `🧰 Bootstrap CDK`: open **GitHub → Actions → 🧰 Bootstrap CDK**, select **Run workflow**, and confirm with **Run workflow**.

This workflow runs:

```bash
cdk bootstrap aws://<account-id>/eu-west-1
```

It creates or updates the CDK bootstrap resources in `eu-west-1`, including the `CDKToolkit` CloudFormation stack and the `/cdk-bootstrap/hnb659fds/version` SSM parameter that CDK deploys expect.

### 6. Deploy the database

Run the GitHub Actions workflow `🚀 Deploy shared Lightsail database`: open **GitHub → Actions → 🚀 Deploy shared Lightsail database**, select **Run workflow**, keep or change the `blueprint_id`, and confirm with **Run workflow**.

Use the default `blueprint_id` unless you intentionally want another PostgreSQL version:

```text
postgres_18
```

### 7. Wait for availability

Run the GitHub Actions workflow `🔎 Database status`: open **GitHub → Actions → 🔎 Database status**, select **Run workflow**, and confirm with **Run workflow**.

Wait until the database state is:

```text
available
```

### 8. Initialize logical databases

Run the GitHub Actions workflow `🗄️ Initialize logical databases`: open **GitHub → Actions → 🗄️ Initialize logical databases**, select **Run workflow**, and confirm with **Run workflow**.

The workflow will:

- make `shared-postgres` public temporarily
- connect from the GitHub runner
- create/update `elfico` and `elfico_app`
- create/update `czyjafakturka` and `czyjafakturka_app`
- store app credentials in AWS Secrets Manager
- return `shared-postgres` to private access in cleanup

### 9. Verify private access

Run the GitHub Actions workflow `🔎 Database status` again: open **GitHub → Actions → 🔎 Database status**, select **Run workflow**, and confirm with **Run workflow**.

Confirm:

```text
publiclyAccessible = false
```

### 10. Connect applications

Each app should use only its own Secrets Manager secret.

`elfico`:

```bash
aws secretsmanager get-secret-value \
  --region eu-west-1 \
  --secret-id /lightsail/shared-postgres/elfico/app-user \
  --query SecretString \
  --output text
```

`czyjafakturka`:

```bash
aws secretsmanager get-secret-value \
  --region eu-west-1 \
  --secret-id /lightsail/shared-postgres/czyjafakturka/app-user \
  --query SecretString \
  --output text
```

Each secret contains:

```json
{
  "database": "elfico",
  "username": "elfico_app",
  "password": "generated-password"
}
```

Both apps use the same Lightsail database endpoint and port, but different database names and users.

### 11. Create a snapshot

Before putting production data into the database, run the GitHub Actions workflow `📸 Create database snapshot`: open **GitHub → Actions → 📸 Create database snapshot**, select **Run workflow**, optionally provide `snapshot_name`, and confirm with **Run workflow**.

After that, deploy each app's own schema migrations from its app repository.

## Local Commands

Compile:

```bash
./gradlew -q compileJava
```

Synthesize:

```bash
cdk synth LightsailSharedPostgresStack
```

Deploy locally:

```bash
cdk deploy LightsailSharedPostgresStack \
  --parameters MasterUserPassword="$LIGHTSAIL_MASTER_USER_PASSWORD"
```

Override the PostgreSQL blueprint:

```bash
cdk deploy LightsailSharedPostgresStack \
  --context blueprintId=postgres_17 \
  --parameters MasterUserPassword="$LIGHTSAIL_MASTER_USER_PASSWORD"
```

## Security Notes

- The database is private by default.
- The initialization workflow temporarily makes it public and always attempts to return it to private access.
- App repositories should never use the master user or master password.
- App credentials are generated and stored in AWS Secrets Manager.
- Prefer requiring approval for the `production` GitHub environment.
