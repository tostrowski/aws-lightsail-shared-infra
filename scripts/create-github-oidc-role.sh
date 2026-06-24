#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-eu-west-1}"
GITHUB_OWNER="${GITHUB_OWNER:-tostrowski}"
GITHUB_REPO="${GITHUB_REPO:-aws-lightsail-shared-infra}"
GITHUB_ENVIRONMENT="${GITHUB_ENVIRONMENT:-production}"
ROLE_NAME="${ROLE_NAME:-github-lightsail-shared-infra}"
POLICY_NAME="${POLICY_NAME:-github-lightsail-shared-infra-rollout}"
OIDC_PROVIDER_URL="https://token.actions.githubusercontent.com"
OIDC_PROVIDER_HOST="token.actions.githubusercontent.com"
OIDC_THUMBPRINT="${OIDC_THUMBPRINT:-6938fd4d98bab03faadb97b34396831e3780aea1}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

ensure_oidc_provider() {
  if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" >/dev/null 2>&1; then
    echo "OIDC provider exists: ${OIDC_PROVIDER_ARN}"
  else
    echo "Creating OIDC provider: ${OIDC_PROVIDER_ARN}"
    if ! aws iam create-open-id-connect-provider \
      --url "$OIDC_PROVIDER_URL" \
      --client-id-list sts.amazonaws.com \
      --thumbprint-list "$OIDC_THUMBPRINT" \
      >/dev/null; then
      echo "OIDC provider creation failed; checking whether it already exists now..."
      aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" >/dev/null
    fi
  fi

  local has_sts_client_id
  has_sts_client_id="$(aws iam get-open-id-connect-provider \
    --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" \
    --query "contains(ClientIDList, 'sts.amazonaws.com')" \
    --output text)"
  if [[ "$has_sts_client_id" != "True" ]]; then
    echo "Adding sts.amazonaws.com client id to OIDC provider"
    aws iam add-client-id-to-open-id-connect-provider \
      --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" \
      --client-id sts.amazonaws.com
  fi

  local has_thumbprint
  has_thumbprint="$(aws iam get-open-id-connect-provider \
    --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" \
    --query "contains(ThumbprintList, '${OIDC_THUMBPRINT}')" \
    --output text)"
  if [[ "$has_thumbprint" != "True" ]]; then
    echo "Updating OIDC provider thumbprint list"
    aws iam update-open-id-connect-provider-thumbprint \
      --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" \
      --thumbprint-list "$OIDC_THUMBPRINT"
  fi
}

ensure_role() {
  if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
    echo "Role exists: ${ROLE_NAME}"
  else
    echo "Creating role: ${ROLE_NAME}"
    if ! aws iam create-role \
      --role-name "$ROLE_NAME" \
      --assume-role-policy-document "file://${trust_policy}" \
      >/dev/null; then
      echo "Role creation failed; checking whether it already exists now..."
      aws iam get-role --role-name "$ROLE_NAME" >/dev/null
    fi
  fi

  for attempt in {1..12}; do
    if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
      return 0
    fi
    echo "Waiting for role to be visible to IAM..."
    sleep 5
  done

  echo "Role did not become visible: ${ROLE_NAME}" >&2
  exit 1
}

require_command aws

AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
OIDC_PROVIDER_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER_HOST}"
ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
REPO_SUBJECT="repo:${GITHUB_OWNER}/${GITHUB_REPO}:environment:${GITHUB_ENVIRONMENT}"

trust_policy="$(mktemp)"
permissions_policy="$(mktemp)"
trap 'rm -f "$trust_policy" "$permissions_policy"' EXIT

cat >"$trust_policy" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${OIDC_PROVIDER_ARN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER_HOST}:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "${OIDC_PROVIDER_HOST}:sub": "${REPO_SUBJECT}"
        }
      }
    }
  ]
}
EOF

cat >"$permissions_policy" <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudformation:*",
        "lightsail:*",
        "secretsmanager:*",
        "ssm:GetParameter",
        "sts:AssumeRole"
      ],
      "Resource": "*"
    }
  ]
}
EOF

echo "AWS account: ${AWS_ACCOUNT_ID}"
echo "AWS region: ${AWS_REGION}"
echo "GitHub subject: ${REPO_SUBJECT}"

ensure_oidc_provider
ensure_role

echo "Updating role trust policy: ${ROLE_NAME}"
aws iam update-assume-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-document "file://${trust_policy}"

echo "Putting inline rollout policy: ${POLICY_NAME}"
aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "$POLICY_NAME" \
  --policy-document "file://${permissions_policy}"

echo
echo "Use this value for the GitHub production environment secret AWS_ROLE_ARN:"
echo "$ROLE_ARN"
echo
echo "Then add LIGHTSAIL_MASTER_USER_PASSWORD as the second production environment secret."
