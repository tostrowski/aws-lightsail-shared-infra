# AWS Lightsail shared PostgreSQL infrastructure

Java AWS CDK project for one shared Lightsail PostgreSQL database in `eu-west-1a`.

Defaults:

- region: `eu-west-1`
- availability zone: `eu-west-1a`
- bundle: `micro_2_0` (`$15/month`, Standard Micro)
- blueprint: `postgres_18`
- public access: `false`
- logical app databases initialized by workflow/script: `elfico`, `czyjafakturka`

## Deploy

The stack needs an initial master password parameter. Do not commit it.

```bash
cdk deploy LightsailSharedPostgresStack \
  --parameters MasterUserPassword='replace-with-strong-password'
```

Override defaults with CDK context when needed:

```bash
cdk deploy LightsailSharedPostgresStack \
  --context blueprintId=postgres_17 \
  --parameters MasterUserPassword='replace-with-strong-password'
```

## Database initialization

The database is private by default. The `Initialize logical databases` GitHub Actions workflow temporarily makes it public, creates/updates app databases and users, then returns it to private access in cleanup.

The workflow stores app-user credentials in AWS Secrets Manager:

- `/lightsail/shared-postgres/elfico/app-user`
- `/lightsail/shared-postgres/czyjafakturka/app-user`

Each app should use only its own app-user secret and run its own schema migrations.
