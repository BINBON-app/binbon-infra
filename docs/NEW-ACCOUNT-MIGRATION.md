# Migrating the platform to a new AWS account

A step-by-step runbook for standing this stack up in a fresh AWS account, written
from an actual migration (account `995192978674` → `803817915623`, `eu-central-1`)
rather than from the design docs. Every step that bit us in practice is called
out, including two that fail on the first run **by design of the AWS services
involved** and simply need a second pass.

The README's [Quick start](../README.md#-quick-start) covers the happy path. This
document is the longer, honest version: the same journey plus the parts that are
not in Terraform.

---

## 0. Know what is *not* in Terraform

Terraform provisions the infrastructure. It does **not** do these, and each one
has caused a full-fleet outage when forgotten:

| Gap | Symptom if skipped | Fixed by |
|---|---|---|
| Per-service Postgres databases | All 20 Postgres services crash-loop: `database "binbon_x" does not exist` | `scripts/db-bootstrap.sh` |
| OpenSearch service-linked role | `CreateDomain` fails: *must enable a service-linked role* | Re-run the apply (see step 7) |
| OpenVPN Marketplace subscription | VPN instance fails to launch | Accept in the Marketplace console |
| GitHub repo variables/secrets | CI pushes images to the *old* account | Set them by hand (step 10) |
| Container images | Every service sits on the `:<name>-replace` placeholder | Run the backend deploy workflow |

---

## 1. Prerequisites

Collect these **before** starting. Several steps block without them.

- **AWS account ID** and admin credentials. If using an access-key profile rather
  than SSO, configure it and note the profile name — every command below assumes
  `AWS_PROFILE` is set to it.
- **Redpanda Cloud**: an organization, a resource group, and a service account
  (`REDPANDA_CLIENT_ID` / `REDPANDA_CLIENT_SECRET`). The service account needs a
  role that can create clusters, topics, users and ACLs — Admin at the
  organization or resource-group scope.
- **ClickHouse Cloud**: `CLICKHOUSE_ORG_ID`, `CLICKHOUSE_CLOUD_API_KEY`,
  `CLICKHOUSE_CLOUD_API_SECRET`.
- **OpenVPN Access Server** Marketplace subscription accepted in the new account.
  Verify without launching anything:
  ```bash
  aws ec2 run-instances --image-id <ami-id> --instance-type t3.small \
    --dry-run --region eu-central-1
  ```
  `DryRunOperation: Request would have succeeded` means the subscription is live.
  An `OptInRequired` error means it is not — accept it in the Marketplace console.

> [!IMPORTANT]
> Credentials are **never** committed and never written to a local file that
> outlives the run. `scripts/bootstrap-secrets.sh` reads them from the
> environment (or prompts) and writes them straight into Secrets Manager.

---

## 2. Preserve the old account's state

Not strictly required, but cheap insurance and it makes rollback a real option.

```bash
cd terragrunt/bootstrap
terragrunt state pull > ../../bootstrap-old-account-<old-account-id>.tfstate
```

`*.tfstate` is gitignored, so this stays local.

---

## 3. Create the new state backend

```bash
export AWS_PROFILE=<new-account-profile>
cd terragrunt/bootstrap
terragrunt init
terragrunt apply
```

Note the `state_bucket` and `lock_table` outputs.

---

## 4. Repoint every reference to the new state bucket

The bucket name is **hardcoded in 21 files** (`root.hcl`, the 16 component
files, and `github-oidc/terragrunt.hcl`) so each component's `remote_state`
resolves without an `include`. Rewrite them all at once:

```bash
OLD="<old-bucket-name>"
NEW="<state_bucket output from step 3>"
grep -rl "$OLD" terragrunt/root.hcl terragrunt/components/ terragrunt/github-oidc/ \
  | xargs sed -i "s/$OLD/$NEW/g"
```

Then **clear the Terragrunt caches**, or the old backend config is reused and you
get confusing "bucket does not exist" failures:

```bash
find terragrunt -type d -name '.terragrunt-cache' -prune -exec rm -rf {} +
```

Verify nothing references the old bucket:

```bash
grep -rn "$OLD" terragrunt/ --include='*.hcl' | grep -v terragrunt-cache
```

---

## 5. Point the environment at the new account

Edit `terragrunt/envs/dev/eu-central-1/env.hcl` and replace every occurrence of
the old account ID (there were 52 in the reference migration — they appear inside
Secrets Manager ARNs, ECR URIs and IAM role ARNs):

```bash
sed -i 's/<old-account-id>/<new-account-id>/g' terragrunt/envs/dev/eu-central-1/env.hcl
```

Keep a `.bak` first. Confirm the count afterwards:

```bash
grep -c '<new-account-id>' terragrunt/envs/dev/eu-central-1/env.hcl
```

---

## 6. Populate Secrets Manager

Export the credentials from step 1, then run the bootstrap. It creates ~25
secrets, generating the platform-wide ones (`JWT_SECRET`, `INTERNAL_API_KEY`) and
one `REDPANDA_SASL_PASSWORD` per service.

```bash
export AWS_PROFILE=<new-account-profile>
export ENVIRONMENT=dev REGION=eu-central-1
export REDPANDA_CLIENT_ID=... REDPANDA_CLIENT_SECRET=...
export CLICKHOUSE_ORG_ID=... CLICKHOUSE_CLOUD_API_KEY=... CLICKHOUSE_CLOUD_API_SECRET=...
./scripts/bootstrap-secrets.sh
```

Anything not exported is prompted for interactively; a blank value is refused
rather than silently stored.

### 6a. Repatch the Redpanda secret ARNs

`env.hcl` stores **literal ARNs**, and Secrets Manager appends a random 6-character
suffix to every new secret. The 19 `REDPANDA_SASL_PASSWORD` ARNs will therefore all
be wrong. Read the real ARNs back from AWS rather than transcribing them — for each
service, `aws secretsmanager describe-secret --secret-id binbon-dev-redpanda-<service>
--query ARN` and substitute.

Anchor the match on the full service name plus `-`, or `user-service` will also
match `video-processing-service`.

Then confirm every ARN in the file resolves:

```bash
grep -oE 'arn:aws:secretsmanager:[^"]+' terragrunt/envs/dev/eu-central-1/env.hcl \
  | sort -u \
  | while read -r a; do
      aws secretsmanager describe-secret --secret-id "$a" --region eu-central-1 \
        >/dev/null 2>&1 || echo "MISSING: $a"
    done
```

> [!TIP]
> Making these ARNs dynamic (a `data` lookup instead of a literal) would remove
> this whole step. It is the single most annoying part of an account move.

---

## 7. Apply the infrastructure

```bash
./scripts/tg.sh run --all --non-interactive -- apply -auto-approve
```

**Expect the first run to fail on `opensearch`**, with:

> ValidationException: Before you can proceed, you must enable a service-linked
> role to give Amazon OpenSearch Service permissions to access your VPC.

This is normal in a fresh account. The failed `CreateDomain` call itself causes
AWS to provision `AWSServiceRoleForAmazonOpenSearchService`, so **simply run the
same command again** and it succeeds. `secrets` and `services` are skipped on the
first run because they sit downstream of `opensearch` in the DAG — they run on the
second pass.

The module carries an `aws_iam_service_linked_role` behind
`create_service_linked_role` (default `true`) for accounts where the role genuinely
does not exist. If the role already exists you get
`InvalidInput: Service role name ... has been taken`; set
`create_service_linked_role = false` in `terragrunt/components/opensearch.hcl`.
It is set to `false` today because the reference account already has the role.

Expect roughly **470 resources** and 30–45 minutes; Aurora and OpenSearch dominate.

---

## 8. Create the per-service databases

**This is the step that is easiest to forget and hardest to diagnose.** Aurora is
created with a single database (`app`); the design is database-per-service, and
those 20 databases are not in Terraform. Without them every Postgres-backed
service crash-loops on `database "binbon_x" does not exist` and the ECS deployment
circuit breaker trips.

```bash
./scripts/db-bootstrap.sh          # dry run — lists what is missing
./scripts/db-bootstrap.sh --apply  # create them
```

It works over the RDS Data API (`enable_http_endpoint = true` on the cluster), so
no VPN or private-subnet access is needed.

---

## 9. Provision the GitHub OIDC roles

```bash
./scripts/tg.sh github-oidc --non-interactive apply -auto-approve
```

Check that `github_org`, `monorepo_name` and `infra_repo_name` in
`terragrunt/github-oidc/terragrunt.hcl` match your **actual git remotes** — the
trust policy is pinned to `repo:<org>/<name>:*`, and a mismatch produces a role
that silently never works. Local directory names often differ from repo names.

Record the outputs: `ecs_deploy_role_arn`, `terraform_apply_role_arn`.

---

## 10. Repoint the backend CI

No workflow file changes are needed — the deploy workflow is fully parameterized.
In the **backend** repo's GitHub settings:

| Setting | Value |
|---|---|
| `vars.ECR_REGISTRY` | `<new-account-id>.dkr.ecr.eu-central-1.amazonaws.com` |
| `vars.ECR_REPOSITORY` | `binbon-dev` |
| `vars.ECS_CLUSTER_PREFIX` | `binbon` |
| `vars.AWS_REGION` | `eu-central-1` |
| `secrets.AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | new account's keys |
| `vars.AWS_ECS_DEPLOY_ROLE_ARN` | from step 9 — only if switching to OIDC |

Branch routing in the deployed workflow is `dev → dev`, `staging → staging`,
`master → prod`.

Then push to `dev` (or run the workflow manually) to build and push real images.
Until this happens every task definition points at the non-existent
`binbon-dev:<service>-replace` placeholder.

---

## 11. Recover any tripped services

A service whose deployment circuit breaker tripped stays `FAILED` even after the
root cause is fixed — it will not retry on its own.

```bash
./scripts/redeploy.sh dev          # dry run
./scripts/redeploy.sh dev --apply  # force new deployments
```

---

## 12. Verify

```bash
./scripts/health-check.sh dev      # all services running? ALB targets healthy?
./scripts/kafka-check.sh dev 30    # broker connections, SASL errors
```

A clean result is every service `OK` with `runningCount == desiredCount` and
rollout `COMPLETED`.

> [!WARNING]
> ECS "healthy" does **not** prove broker connectivity. The events crate's
> `warm()` has a 5-second timeout and deliberately does not block startup, so a
> producer reports healthy while silently failing to reach Redpanda. Confirm with
> `kafka-check.sh` (look for `rskafka::connection::topology: New broker`, which
> only appears after a successful SASL handshake) or with consumer-group activity
> on the cluster.

---

## Post-migration notes

- **SASL mechanism.** The backend supports `SCRAM-SHA-256` (default),
  `SCRAM-SHA-512` and `PLAIN`, selected by `KAFKA_SASL_MECHANISM`. Nothing in the
  infra sets it, so the SCRAM-SHA-256 default applies. Consider setting it
  explicitly so the mechanism is visible in the task definition rather than
  implied by a Rust fallback.
- **Redis is cluster-mode.** ElastiCache Serverless always is. Any multi-key
  Redis command (`ZUNIONSTORE`, `MGET`, `RENAME`, …) fails with `CROSSSLOT`
  unless all its keys share a hash tag.
- **No ERROR alerting exists.** A `tracing::error!` firing every 30 seconds went
  unnoticed for the life of a service. A CloudWatch metric filter over the
  `/ecs/binbon-<env>/*` log groups is worth adding.
