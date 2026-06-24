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
- `♻️ Restore database snapshot`: creates a new private database from a manual snapshot.

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

Each app should use only its own Secrets Manager secret. Do not copy the password into `application.yaml`, the repository, or a GitHub variable.

`elfico`:

```text
/lightsail/shared-postgres/elfico/app-user
```

`czyjafakturka`:

```text
/lightsail/shared-postgres/czyjafakturka/app-user
```

Each secret contains:

```json
{
  "database": "elfico",
  "username": "elfico_app",
  "password": "generated-password"
}
```

The current app deployment workflows start the Spring Boot JAR over SSH. In each app repository, update its deploy workflow to retrieve that app's secret and inject the connection settings into the Java process:

```bash
DB_SECRET_ID=/lightsail/shared-postgres/elfico/app-user # change for czyjafakturka

DB_SECRET_JSON="$(aws secretsmanager get-secret-value \
  --region eu-west-1 \
  --secret-id "$DB_SECRET_ID" \
  --query SecretString \
  --output text)"

DB_HOST="$(aws lightsail get-relational-database \
  --region eu-west-1 \
  --relational-database-name shared-postgres \
  --query 'relationalDatabase.masterEndpoint.address' \
  --output text)"
DB_PORT="$(aws lightsail get-relational-database \
  --region eu-west-1 \
  --relational-database-name shared-postgres \
  --query 'relationalDatabase.masterEndpoint.port' \
  --output text)"
DB_NAME="$(jq -r '.database' <<<"$DB_SECRET_JSON")"
DB_USERNAME="$(jq -r '.username' <<<"$DB_SECRET_JSON")"
DB_PASSWORD="$(jq -r '.password' <<<"$DB_SECRET_JSON")"
DB_URL="jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}"

# Prevent accidental disclosure in subsequent GitHub Actions log output.
echo "::add-mask::$DB_USERNAME"
echo "::add-mask::$DB_PASSWORD"

# Preserve special characters when values are passed through SSH.
printf -v DB_URL_ESCAPED '%q' "$DB_URL"
printf -v DB_USERNAME_ESCAPED '%q' "$DB_USERNAME"
printf -v DB_PASSWORD_ESCAPED '%q' "$DB_PASSWORD"

ssh ec2-user@"$INSTANCE_IP" <<EOF
export SPRING_DATASOURCE_URL=$DB_URL_ESCAPED
export SPRING_DATASOURCE_USERNAME=$DB_USERNAME_ESCAPED
export SPRING_DATASOURCE_PASSWORD=$DB_PASSWORD_ESCAPED
nohup java -Dspring.profiles.active=aws -jar /home/ec2-user/app.jar > /home/ec2-user/app.log 2>&1 &
EOF
```

Use the actual JAR filename from the app's deployment workflow. Spring Boot maps these environment variables to `spring.datasource.url`, `spring.datasource.username`, and `spring.datasource.password`; no password belongs in the application configuration file.

The AWS identity used by the app's deployment workflow needs:

```text
secretsmanager:GetSecretValue
lightsail:GetRelationalDatabase
```

Restrict `secretsmanager:GetSecretValue` to that app's secret ARN. The app server does not need permission to read Secrets Manager because the deployment workflow retrieves the secret and passes it directly to the application process.

Both apps use the same Lightsail database endpoint and port, but different database names, users, and passwords.

### Connect with `psql` while the database is public

Use this only for temporary administrative access from your local machine. The complete procedure is:

1. Make the database public.
2. Wait until the access change is complete.
3. Connect with `psql` and perform the required work.
4. Disconnect; the connection script exits and discards the retrieved credentials.
5. Make the database private again, even if the database work failed.
6. Verify that private access has been restored.

The repository includes the workflows required for this procedure:

- [`🔐 Set database access`](.github/workflows/set-db-access.yml) changes `shared-postgres` between public and private access.
- [`🔎 Database status`](.github/workflows/db-status.yml) reports the database state, endpoint, port, and current `publiclyAccessible` value.

Both workflows authenticate through the `production` environment's `AWS_ROLE_ARN` secret.

#### 1. Make the database public

In GitHub, open **Actions → 🔐 Set database access → Run workflow**, select `public`, and run the workflow.

Next, run **Actions → 🔎 Database status → Run workflow** until it reports:

```text
state = available
publiclyAccessible = true
```

Do not start the local connection until both values are confirmed.

#### 2. Connect and perform the work

The connection script requires an authenticated AWS CLI session with `lightsail:GetRelationalDatabase` and `secretsmanager:GetSecretValue` permissions, plus `psql` and `jq` installed locally. It verifies that the database is available and public, retrieves the selected application's credentials, and starts a TLS-enabled `psql` session.

Connect to the required application database:

```bash
./scripts/connect-to-database.sh elfico
# or
./scripts/connect-to-database.sh czyjafakturka
```

Run the required SQL commands. Use the app-specific user for routine work; do not use the master user unless the operation specifically requires administrative privileges.

Exit `psql` with:

```text
\q
```

The script passes the password only to the `psql` process, so no credentials are exported into the current shell.

#### 3. Make the database private again

This step is required even if the `psql` connection or SQL work failed. In GitHub, open **Actions → 🔐 Set database access → Run workflow**, select `private`, and run the workflow.

#### 4. Verify private access

Run **Actions → 🔎 Database status → Run workflow** until it reports:

```text
state = available
publiclyAccessible = false
```

The procedure is not complete until private access is confirmed. Public database access exposes the endpoint to the internet, so keep the public window as short as possible.

### 11. Create a snapshot

A snapshot is a point-in-time copy of the entire managed PostgreSQL database. It provides a recovery point if a schema migration, deployment, administrative command, or application bug damages the database. Lightsail restores a snapshot by creating a new database from it; it does not roll back the existing database in place. After a restore, update the applications to use the restored database's endpoint.

Create the first snapshot after initialization and before applying the applications' schema migrations. At that point it records a known-good database with the logical databases, users, and permissions configured. It will not contain production data if none has been written yet, so it is only a clean baseline—not a production-data backup.

Also create a snapshot:

- immediately before a risky or destructive schema migration
- before a major application release that changes stored data
- before deleting, recreating, or significantly reconfiguring the database
- when you need a longer-lived recovery point independent of routine backups

Run the GitHub Actions workflow `📸 Create database snapshot`: open **GitHub → Actions → 📸 Create database snapshot**, select **Run workflow**, optionally provide a descriptive `snapshot_name`, and confirm with **Run workflow**. For example:

```text
shared-postgres-before-elfico-migration-20260624
```

Wait until the snapshot is available before starting the risky operation. Creating a snapshot of this standard, non-high-availability database can make it unavailable for a short period, so schedule production snapshots during a maintenance window.

A snapshot is a recovery measure, not a substitute for testing migrations or maintaining an appropriate recurring backup and retention policy.

After that, deploy each app's own schema migrations from its app repository.

### 12. Restore from a snapshot

Restoring does not modify or roll back `shared-postgres`. Lightsail creates a separate database with a new resource name and endpoint. The original database remains available, and both databases are billed until one is deleted.

Use a restore when the current database cannot be repaired safely—for example, after a destructive migration or accidental data deletion:

1. Stop application writes to `shared-postgres` so that no additional data is created during recovery.
2. Identify the snapshot to restore in **AWS Lightsail → Databases → Snapshots**, or list snapshots with:

   ```bash
   aws lightsail get-relational-database-snapshots \
     --region eu-west-1 \
     --query 'relationalDatabaseSnapshots[].{name:name,state:state,createdAt:createdAt,source:fromRelationalDatabaseName}' \
     --output table
   ```

3. Run the GitHub Actions workflow `♻️ Restore database snapshot`: open **GitHub → Actions → ♻️ Restore database snapshot**, select **Run workflow**, and provide:

   - `snapshot_name`: the exact name of an `available` snapshot
   - `restored_database_name`: a new name, such as `shared-postgres-restored-20260624`
   - `bundle_id`: keep `micro_2_0`, or choose a larger compatible plan; Lightsail does not allow a plan smaller than the snapshot's source plan
   - `confirmation`: enter `RESTORE`

4. Wait for the workflow to report the restored database as `available`. The workflow creates it in `eu-west-1a` with public access disabled and prints its new endpoint.
5. Verify the restored data before directing production traffic to it. The snapshot contains the database users and passwords that existed when it was created. The existing Secrets Manager values will work only if they still match those snapshot credentials.
6. Point each application at the restored database. Do this in both the `elfico` and `czyjafakturka` repositories:

   - Open **GitHub → repository → Settings → Environments → production → Environment variables**.
   - Create or update `LIGHTSAIL_DB_NAME` with the restored resource name, for example:

     ```text
     shared-postgres-restored-20260624
     ```

   - In `.github/workflows/deploy-app.yml`, add `LIGHTSAIL_DB_NAME` to the existing `env` block of the step that retrieves the database endpoint:

     ```yaml
     - name: Start New Application
       env:
         LIGHTSAIL_DB_NAME: ${{ vars.LIGHTSAIL_DB_NAME }}
       run: |
         if [ -z "$LIGHTSAIL_DB_NAME" ]; then
           echo "::error::LIGHTSAIL_DB_NAME is not configured."
           exit 1
         fi

         DB_HOST="$(aws lightsail get-relational-database \
           --region eu-west-1 \
           --relational-database-name "$LIGHTSAIL_DB_NAME" \
           --query 'relationalDatabase.masterEndpoint.address' \
           --output text)"
         DB_PORT="$(aws lightsail get-relational-database \
           --region eu-west-1 \
           --relational-database-name "$LIGHTSAIL_DB_NAME" \
           --query 'relationalDatabase.masterEndpoint.port' \
           --output text)"

         # Continue with the app-specific secret lookup from section 10.
         DB_URL="jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}"
     ```

   - Pass `DB_URL`, `DB_USERNAME`, and `DB_PASSWORD` through SSH as shown in section 10 and start the JAR with:

     ```bash
     export SPRING_DATASOURCE_URL="$DB_URL"
     export SPRING_DATASOURCE_USERNAME="$DB_USERNAME"
     export SPRING_DATASOURCE_PASSWORD="$DB_PASSWORD"
     ```

   `LIGHTSAIL_DB_NAME` is a GitHub environment variable, not a secret. It selects the Lightsail resource whose endpoint is used. Keep the password in the app-specific Secrets Manager secret.

   After changing the variable, run the GitHub Actions workflow `🚀 Deploy App` in the `elfico` repository and then in the `czyjafakturka` repository: open **GitHub → Actions → 🚀 Deploy App**, select **Run workflow**, and confirm with **Run workflow**. The redeployed processes will resolve the restored database's endpoint and connect to it.

   To roll back the cutover, set `LIGHTSAIL_DB_NAME` back to `shared-postgres` in both repositories and run each repository's `🚀 Deploy App` workflow again.

7. Confirm both applications can read and write the restored database before resuming traffic.

Do not delete `shared-postgres` immediately. Keep it until the restored database has been validated and the required recovery data is confirmed. The restored database is created outside the CDK stack, so subsequent CDK deployments continue to manage `shared-postgres`, not the restored resource. Decide separately whether to retain the restored database temporarily, promote it through an application configuration change, or migrate its recovered data back into the CDK-managed database.

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
