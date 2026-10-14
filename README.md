<div align="center">

# 🌍 Binbon AWS Serverless Platform

**A modular, multi-environment AWS foundation powered by Terraform + Terragrunt**

![AWS Frankfurt](https://img.shields.io/badge/AWS-Frankfurt%20%28eu--central--1%29-FF9900?logo=amazonaws&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-%3E%3D%201.6-7B42BC?logo=terraform&logoColor=white)
![Terragrunt](https://img.shields.io/badge/Terragrunt-%3E%3D%200.66-5C4EE5?logo=terraform&logoColor=white)
![Environments](https://img.shields.io/badge/Environments-dev%20%7C%20staging%20%7C%20prod-16A34A)

</div>

> [!IMPORTANT]
> The workload is pinned to **AWS Frankfurt (`eu-central-1`)**. CloudFront viewer certificates and CloudFront-scoped WAF Web ACLs are the AWS exception: they must be created in **`us-east-1`**. Application compute and data remain in Frankfurt.

---

## 🗺️ Platform at a glance

| Area | Included services | Purpose |
| :-- | :-- | :-- |
| 🟦 **Network** | VPC, 3 subnet tiers, NAT, Flow Logs | Multi-AZ private foundation |
| 🟩 **Compute** | ALB, ECS Fargate, ECR, IAM, CloudWatch | Containerised microservices with autoscaling |
| 🟪 **Data** | Aurora Serverless v2, ElastiCache Serverless, Keyspaces, OpenSearch, ClickHouse Cloud | PostgreSQL, Redis, wide-column, search and OLAP analytics |
| 🟨 **Edge & media** | WAF on the ALB (managed rule groups + rate limiting), CloudFront for media, S3, MediaConvert | Abuse filtering in front of the API, and media delivery |
| 🟥 **Identity** | none in AWS | Login lives in the backend: auth-service issues OTPs and signs its own JWTs with `JWT_SECRET` |
| 🟧 **Events** | Redpanda Serverless + AWS PrivateLink | Kafka-compatible event streaming |
| ⚙️ **Operations** | KMS, Secrets Manager hooks, remote state bootstrap | Encryption, logs and state management |

> [!NOTE]
> **Agora/ZEGOCLOUD** (live/chat signalling) remains an externally managed service. Configure its endpoint and secret ARN in an environment `env.hcl`; never put secret values in Terraform state.
>
> This directory is a fork of the dev-only `binbon-aws-terraform-dev` baseline, extended to close the gaps against the target architecture: a real WAF Web ACL (previously just an attachment hook), and Terraform-managed OpenSearch and ClickHouse Cloud (previously undocumented externally-managed services). ECS service definitions in `env.hcl` still only cover `api-gateway`; expanding to the full service catalog is a deliberately separate follow-up.

---

## ✅ Before you begin

| Required | Why |
| :-- | :-- |
| Terraform `>= 1.6` + Terragrunt `>= 0.66` | Provision and orchestrate the stack |
| AWS credentials / CI role | Access the target AWS account |
| ACM certificate in `eu-central-1` | ALB HTTPS listener. One wildcard per environment, e.g. `*.dev.binbon.ch`, requested with `scripts/request-certs.sh` |
| ACM certificate in `us-east-1` | Only for a custom domain on the media CloudFront |
| Redpanda Cloud service account | Needed only for the Redpanda stack |
| ClickHouse Cloud organization + API key | Needed only for the ClickHouse stack |

> [!CAUTION]
> Do not commit `env.hcl`, `.tfstate` files, provider credentials, or password values. The supplied `.gitignore` protects the common cases, but CI secret handling is still essential.

---

## 🚀 Quick start

### 1) Prepare the target environment

Copy the sample environment file and set the environment's settings. The AWS account is not in it: that is `terragrunt/backend.hcl` (step 2). Leave the certificate ARNs `null` until the certificates exist.

```powershell
cd terragrunt/envs/dev/eu-central-1
Copy-Item env.hcl.example env.hcl
```

### 2) Bootstrap Terraform state

```powershell
cd ../../../bootstrap
terragrunt init
terragrunt apply
```

Put the outputs, and the account ID, in **`terragrunt/backend.hcl`**. It's the only file that names the account and its state backend; every component and `github-oidc` read it:

```hcl
locals {
  account_id   = "<aws account id>"
  state_bucket = "<state_bucket output>"
  lock_table   = "<lock_table output>"
  state_region = "eu-central-1"
}
```

`account_id` also builds the ECR image URIs and puts `allowed_account_ids` on every AWS provider, so a shell pointed at the wrong account fails at plan time.

You only need this the first time you bootstrap an environment, or if you ever re-bootstrap after a full teardown (see [Troubleshooting](#-troubleshooting) below).

### 3) Plan and apply

```powershell
cd ../envs/dev/eu-central-1
terragrunt run-all plan
terragrunt run-all apply
```

> [!TIP]
> Switch environments by changing directory, not Terraform workspaces. This keeps state and account targets clearly separated.

```powershell
cd terragrunt/envs/staging/eu-central-1
terragrunt run-all plan

cd ../../prod/eu-central-1
terragrunt run-all plan
```

---

## 🔁 Deployment flow

```text
network
  ├── foundation ──┬── alb ──┬── data ── vpn
  │                │   │    └── opensearch
  │                │   └── waf-regional
  │                └── media ── waf-cloudfront
  ├── clickhouse
  └── redpanda ── redpanda-endpoint
                       │
                       ▼
                    services
```

| Stack | Deploys | Depends on |
| :-- | :-- | :-- |
| `network` | VPC, subnets, NAT, Flow Logs | — |
| `foundation` | KMS and ECR | — |
| `alb` | Public ALB and ECS task security group | `network` |
| `data` | Aurora, Redis, Keyspaces | `network`, `foundation`, `alb` |
| `opensearch` | VPC-attached OpenSearch domain | `network`, `foundation`, `alb` |
| `clickhouse` | ClickHouse Cloud service | `network` (NAT egress IP allow-list) |
| `media` | S3 (private by default; dev is public-read, see the migration runbook), CloudFront and MediaConvert role | `foundation`, `waf-cloudfront` |
| `waf-cloudfront` | CloudFront-scope WAF Web ACL (`us-east-1`) | — |
| `waf-regional` | Regional-scope WAF Web ACL (`eu-central-1`), attached to the ALB | — |
| `vpn` | OpenVPN Access Server for operator access into the VPC; `reachable_ports` opens chosen private services (dev: Aurora 5432) to VPN clients | `network`, `alb`, `data` |
| `redpanda` | Serverless cluster, topics, users and ACLs | — |
| `redpanda-endpoint` | AWS PrivateLink endpoint and private DNS | `network`, `alb`, `redpanda` |
| `services` | ECS tasks and autoscaling | Platform dependencies above |

---

## 🚢 Building & deploying services (CI/CD)

Application deploys are deliberately **outside Terraform**. Terraform/Terragrunt provisions the ECS cluster, service, task definition shape, target group, and IAM roles — structural, infrequent changes. Which container image is actually running is owned entirely by CI calling the ECS API directly (`register-task-definition` + `update-service`), which can happen many times a day without touching Terraform state or fighting Terraform's own state lock across all 31 services.

Each environment has a single ECR repository (`foundation` module — `binbon-dev`, `binbon-staging`, `binbon-prod`), shared by all services and differentiated by tag: `<service-name>-<git-sha>` (e.g. `api-gateway-a1b2c3d`). The repository has `image_tag_mutability = "IMMUTABLE"` — **re-pushing an existing tag always fails**, so every build must use a unique tag; the service-prefixed git SHA is the convention used here.

> [!IMPORTANT]
> `modules/ecs-services`'s `aws_ecs_service` resource has `lifecycle { ignore_changes = [desired_count, task_definition] }`. This is what makes the split safe: without it, the next unrelated `terraform apply` (e.g. a WAF rule change) would silently force the service back onto whatever task definition Terraform's own state still remembers, undoing every CI deploy since. The tradeoff is the reverse direction isn't automatic either — see "Reconciling after an infra-only change" below.

### Topology: one monorepo, one infra repo

- **Monorepo** — application source, one directory per service (`services/<name>/Dockerfile`). Builds, pushes to ECR, and deploys — entirely by itself, no other repo involved.
- **This infra repo** — owns `terragrunt/`. Structural changes are applied manually via a `workflow_dispatch`-triggered pipeline, independent of and much less frequent than app deploys.

Each repo's CI only needs AWS credentials scoped to what it actually does: the monorepo can push images and update ECS services, but can't touch Terraform state, IAM roles broadly, or any other AWS resource; the infra repo can run Terraform but never builds or holds application code.

### One-time setup

1. **Provision the GitHub OIDC trust** (once per AWS account — this is why it lives in `terragrunt/github-oidc/`, a sibling of `bootstrap`, not under `envs/`):
   ```bash
   cd terragrunt/github-oidc
   # edit terragrunt.hcl: set github_org, monorepo_name, infra_repo_name
   terragrunt init
   terragrunt apply
   ```
   This creates the OIDC identity provider plus two IAM roles — `binbon-github-ecs-deploy` (ECR push + `DescribeTaskDefinition`/`RegisterTaskDefinition`/`UpdateService`/`DescribeServices` + `PassRole` scoped to `binbon-*` roles, trusted only by the monorepo) and `binbon-github-terraform-apply` (`PowerUserAccess` + IAM actions scoped to `binbon-*` roles, trusted only by this infra repo). No static AWS keys are stored in either repo.

   > [!NOTE]
   > `PowerUserAccess` plus a scoped IAM allowance is a pragmatic middle ground for the Terraform-apply role — broad enough that `terragrunt apply` won't hit surprise `AccessDenied` errors as new resource types are added, without granting full `AdministratorAccess` or unrestricted IAM. Tighten it to a fully least-privilege policy before this pipeline touches a real production account.

2. **Copy the workflow template** from `ci-templates/monorepo/.github/workflows/build-and-deploy.yml` into the monorepo at the same path. Add one entry to its `paths-filter` block per service directory.

3. **Monorepo** — add repository variable `AWS_ECS_DEPLOY_ROLE_ARN` (the `ecs_deploy_role_arn` output from step 1).

4. **Infra repo** — add repository variable `AWS_TERRAFORM_APPLY_ROLE_ARN` (the `terraform_apply_role_arn` output). Under **Settings → Environments**, create `dev`, `staging`, and `prod`; add required reviewers to `staging`/`prod` — both `build-and-deploy.yml` and `terraform-apply.yml` target `environment: <name>` at the job level, so this same setting gates *both* app deploys and infra changes for those environments.

### What happens on a push

Branch determines the target environment: `main` → `dev`, `staging` → `staging`, `production` → `prod`. On a push touching `crates/**`, `paths-filter` determines which services changed, then each changed service is fanned out in parallel across two jobs:

1. **`build`** — build the service's Dockerfile (repo root as build context) and push it to that environment's single ECR repository, tagged `<service-name>-<commit-sha>`.
2. **`deploy`** (needs `build`) — `describe-task-definition` the current revision, patch its image field to the same `<service-name>-<commit-sha>` tag (recomputed, not passed between jobs — the tag is deterministic), `register-task-definition`, `update-service --force-new-deployment`, then `ecs wait services-stable` — so the workflow fails loudly if the new image can't reach a healthy state, rather than reporting a false success.

A manual `workflow_dispatch` run (pick environment + service) follows the same two jobs, skipping `detect-changes`/`paths-filter` entirely.

### Reconciling after an infra-only change

Since the service ignores `task_definition` drift, a legitimate Terraform-driven change (e.g. bumping `cpu`/`memory` in `env.hcl`) creates a new task definition revision that the running service **won't** pick up automatically. Terraform's current revision is available as an output for exactly this:

```bash
cd terragrunt/envs/dev/eu-central-1/services
terragrunt output -json task_definition_arns
# then, once you've confirmed it's the revision you want running:
aws ecs update-service --cluster binbon-dev --service api-gateway \
  --task-definition "<arn-from-above>" --force-new-deployment
```

This is a deliberate manual step, not an oversight — it keeps infra changes from silently redeploying application code (or vice versa).

### Manual deploy (before CI is wired up, or for a one-off)

```bash
export AWS_PROFILE=<profile>
ACCOUNT=<account-id>
TAG="api-gateway-$(git rev-parse --short HEAD)"
REPO="$ACCOUNT.dkr.ecr.eu-central-1.amazonaws.com/binbon-dev"

aws ecr get-login-password --region eu-central-1 | \
  docker login --username AWS --password-stdin "$ACCOUNT.dkr.ecr.eu-central-1.amazonaws.com"

docker build -t "$REPO:$TAG" ./api-gateway
docker push "$REPO:$TAG"

aws ecs describe-task-definition --task-definition binbon-dev-api-gateway \
  --query taskDefinition > task-def.json

jq --arg IMAGE "$REPO:$TAG" '
  .containerDefinitions[0].image = $IMAGE
  | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)
' task-def.json > task-def-patched.json

NEW_ARN=$(aws ecs register-task-definition --cli-input-json file://task-def-patched.json \
  --query 'taskDefinition.taskDefinitionArn' --output text)

aws ecs update-service --cluster binbon-dev --service api-gateway \
  --task-definition "$NEW_ARN" --force-new-deployment

aws ecs wait services-stable --cluster binbon-dev --services api-gateway
```

---

## 🔑 Operator access: VPN and databases

The `vpn` component runs OpenVPN Access Server on a small EC2 instance with an
Elastic IP. It configures itself on first boot, and clients get a split tunnel:
only the VPC (`10.20.0.0/16`) goes through it.

- **Logins:** `scripts/vpn-user.sh` creates, resets and removes them over SSM
  and keeps every password in Secrets Manager (`binbon-<env>-vpn-*`). The SSM
  command carries only the secret's name, and the host reads the value itself.
  `profile <user>` saves a `.ovpn` for **OpenVPN Connect**, or import by URL,
  `https://<vpn-ip>`.
- **What VPN clients can reach:** Access Server passes client traffic on as the
  VPN instance, so each private service must admit the VPN's security group.
  `reachable_ports` in `components/vpn.hcl` lists them. Dev opens Aurora on
  5432, so pgAdmin connects to the cluster endpoint with SSL mode `require`
  (`rds.force_ssl = 1`).
- **Database credentials:** the master user's password is RDS-managed and
  **rotates about every 7 days**, so re-read its secret when a saved password
  stops working. See `docs/NEW-ACCOUNT-MIGRATION.md`, step 13.
- **After a migration:** the VPN address, the Aurora endpoint and its password
  secret are all new, and logins don't carry over. Re-create them with
  `vpn-user.sh`, import the new profile (delete the old one), and edit the
  saved pgAdmin server.

> [!WARNING]
> The admin web UI (943) and SSH (22) are open to `admin_cidrs`, which is
> `0.0.0.0/0` by default. Narrow it to your own addresses in `env.hcl`. The
> VPN ports (1194/udp, 443/tcp) stay public so clients can connect from
> anywhere.

---

## 🛡️ WAF configuration

Two separate Web ACLs exist because AWS WAF scopes are not interchangeable:

- `waf-cloudfront` — scope `CLOUDFRONT`, must be created in `us-east-1` regardless of where the rest of the platform runs. Attached to the media CloudFront distribution.
- `waf-regional` — scope `REGIONAL`, created in `eu-central-1`. Attached to the ALB, so it sits in front of every API request. In its common rule set, two body rules only **count** (`common_rules_count_only`), because multipart uploads go through api-gateway: `SizeRestrictions_BODY` blocks bodies over 8 KB, and `CrossSiteScripting_BODY` read raw video bytes as markup and blocked video and reel uploads. Requests without a `User-Agent` header are blocked (`NoUserAgent_HEADER`).

There is no CloudFront in front of the API. It used to be planned (the `edge` component), but API responses are per user and can't be cached, so it added cost and a second WAF without much benefit. The ALB, its WAF and Terraform-owned HTTPS replace it.

Both ship with a per-IP rate-based rule (`rate_limit`, default 2000 requests/5 minutes) plus the AWS managed rule groups `AWSManagedRulesCommonRuleSet`, `AWSManagedRulesKnownBadInputsRuleSet`, and `AWSManagedRulesAmazonIpReputationList`. Adjust `rate_limit` per environment in `terragrunt/components/waf-cloudfront.hcl` / `waf-regional.hcl` if traffic patterns require it.

---

## 🔍 OpenSearch & 📊 ClickHouse Cloud configuration

**OpenSearch** runs inside the VPC's data-private subnets, reachable only from the ECS task security group on port 443, encrypted at rest with the platform KMS key. Size it per environment via the `opensearch` block in `env.hcl` (`instance_type`, `instance_count`, `volume_size_gb`); `instance_count > 1` turns on zone awareness automatically.

> [!NOTE]
> The **first** VPC-based OpenSearch domain ever created in an AWS account needs the `AWSServiceRoleForAmazonOpenSearchService` service-linked role. `terragrunt/bootstrap` creates it (`service_linked_roles`), once per account and before any component runs, so `opensearch` no longer fails with `you must enable a service-linked role` on a fresh account. Where the role already exists, import it into bootstrap instead (see the migration runbook, step 7).

**ClickHouse Cloud** is provisioned through the [`ClickHouse/clickhouse`](https://registry.terraform.io/providers/ClickHouse/clickhouse/latest) provider and IP-allow-listed to the environment's NAT gateway public IP(s), so only traffic actually leaving the VPC can reach it. Provider version is pinned loosely (`>= 1.0.0`) — confirm the resolved version in `.terraform.lock.hcl` after the first `terragrunt init` and tighten the constraint in `modules/clickhouse/versions.tf` if you want a hard pin.

> [!IMPORTANT]
> This module does **not** use the legacy `tier` argument (`"development"`/`"production"`) — organizations on ClickHouse Cloud's current (non-legacy) pricing model have it rejected outright by the API with `Service tier is not supported`. Instead, size the service per environment via the `clickhouse` block in `env.hcl`: `num_replicas`, `min_replica_memory_gb`, and `max_replica_memory_gb` (fixed-size vertical scaling; set min == max for a non-autoscaling service). Whenever `idle_scaling = true`, `idle_timeout_minutes` must also be set — the module defaults it to `5`.

With `idle_scaling` on, ClickHouse suspends after 5 idle minutes and takes longer to wake than analytics-service's 15-second request timeout. If analytics starts against a sleeping service it logs `ensure_database failed` and runs on without its database; wake ClickHouse and force a new deployment of analytics while it's awake.

### Credentials

`terragrunt/components/clickhouse.hcl` fetches the ClickHouse Cloud API credentials (org ID/API key/secret, for the `clickhouse` provider itself) and the ClickHouse admin password directly from AWS Secrets Manager (`<name>-clickhouse-cloud-api`, `<name>-clickhouse-admin-password`) via `run_cmd()` — no `TF_VAR_*`/`CLICKHOUSE_*` env var export needed. Run `scripts/bootstrap-secrets.sh` once per AWS account to seed both. `admin_password` is passed as a write-only provider field (`password_wo` / `password_wo_version`), so it is never persisted to Terraform state.

---

## 🟧 Redpanda Cloud configuration

The Redpanda stack provisions a **Serverless cluster in Frankfurt**, its resource group, Kafka topics, SCRAM-SHA-256 service users, least-privilege ACLs, and an AWS PrivateLink connection.

### Credentials

`terragrunt/components/redpanda.hcl` fetches the Redpanda Cloud API credentials (for the `redpanda` provider itself) and every `service_users` entry's password directly from AWS Secrets Manager (`<name>-redpanda-cloud-api`, one `<name>-redpanda-<service>` secret per service) via `run_cmd()` — no `TF_VAR_*`/`REDPANDA_CLIENT_ID` env var export needed. Run `scripts/bootstrap-secrets.sh` once per AWS account to seed all of these; it also creates the matching `REDPANDA_SASL_PASSWORD` secret each ECS service reads. `service_user_passwords` uses write-only provider fields, so passwords are not stored in Terraform state.

### Redpanda deployment sequence

1. Apply `redpanda`.
2. Apply `redpanda-endpoint`; it consumes the generated PrivateLink service name and Availability Zone IDs from `redpanda`'s outputs.
3. Apply `services`.

That's it — a single pass. `redpanda-endpoint` sets `private_dns_enabled = true` directly on the AWS interface endpoint, so the cluster's public hostname resolves privately inside the VPC automatically; no separate Route 53 zone or second apply is needed.

To retrieve the private Kafka bootstrap hostname for client configuration or debugging (e.g. to confirm what ECS tasks will actually connect to), read it straight from Terraform rather than the Redpanda Cloud console:

```bash
cd terragrunt/envs/<env>/eu-central-1/redpanda
terragrunt output -json kafka_private_seed_brokers
```

Kafka client baseline: `SASL_SSL`, `SCRAM-SHA-256`, port `9092`, and `connections.max.idle.ms < 350000`.

---

## 🧯 Troubleshooting

**`ResourceAlreadyExistsException` / `EntityAlreadyExists` on a fresh apply.** If an environment was ever torn down and its state bucket deleted without first destroying the AWS resources (or without destroying everything), a brand-new bootstrap + apply can collide with orphaned leftovers — most commonly the VPC flow-logs CloudWatch Log Group. Terraform can't create something that already exists, but it can adopt it:

```bash
cd terragrunt/envs/<env>/eu-central-1/network
terragrunt import aws_cloudwatch_log_group.flow_logs "/aws/vpc/binbon-<env>/flow-logs"
terragrunt apply
```

The same pattern (`terragrunt import <resource address> <real ID>`) applies to any other orphaned resource a fresh apply collides with — check the error message for the resource address and the AWS console/CLI for its current ID.

**`Failed to get existing workspaces: S3 bucket ... does not exist`.** The `state_bucket` in `terragrunt/backend.hcl` doesn't match a bucket that actually exists — either bootstrap hasn't been run yet, or a previous bucket was deleted (e.g. during a full environment teardown) and the new one was never copied in. Re-run `terragrunt apply` in `terragrunt/bootstrap`, then put its `state_bucket` output in `terragrunt/backend.hcl` and clear the `.terragrunt-cache` directories (except `terragrunt/bootstrap`'s, which holds bootstrap's local state).

---

## 🛡️ Production checklist

- [ ] Use a dedicated CI role per environment and account.
- [ ] Enable deletion protection, backups, and final snapshots before the first production apply.
- [ ] Set `terragrunt/backend.hcl` (or an environment's own `envs/<env>/backend.hcl`) to the production account, and replace example certificate ARNs, domains and secret ARNs.
- [ ] Restrict ECS egress further or add VPC endpoints if your compliance controls require it.
- [ ] Review Keyspaces schemas and database migrations through your application delivery process.
- [ ] Confirm the resolved `ClickHouse/clickhouse` provider version in `.terraform.lock.hcl` matches what you validated; the module pins a loose `>= 1.0.0` constraint.
- [ ] Review WAF `rate_limit` thresholds against real traffic before launch; both ACLs default to 2000 req/5min per IP.
- [ ] Run `terragrunt run-all plan` in CI and review it before every production apply.

---

## 📁 Repository layout

```text
modules/                         # Reusable Terraform modules
  network/                       # VPC and subnet tiers
  ecs-services/                  # ECS Fargate services and autoscaling
  data/                          # Aurora, Redis and Keyspaces
  opensearch/                    # VPC-attached OpenSearch domain
  clickhouse/                    # ClickHouse Cloud service
  waf/                           # CloudFront/Regional WAF Web ACLs
  redpanda/                      # Serverless Kafka-compatible event bus
  redpanda-vpc-endpoint/         # AWS PrivateLink and private DNS
  vpn/                           # OpenVPN Access Server + what VPN clients may reach
  github-oidc/                   # GitHub Actions OIDC provider + CI IAM roles

terragrunt/
  bootstrap/                     # S3 state bucket and DynamoDB lock table (once per account)
  github-oidc/                   # GitHub Actions trust + IAM roles (once per account)
  components/                    # Reusable Terragrunt component definitions
  envs/dev|staging|prod/         # Isolated live environments

.github/workflows/
  terraform-apply.yml            # This repo: manual, infra-only changes — never per-deploy
  kafka-apply.yml                # Plans/applies redpanda for env.hcl PRs (the backend's auto/kafka-* PRs)
  services-apply.yml             # Plans/applies services for services.hcl PRs (the backend's auto/config-* PRs)
  rotation-restart.yml           # Daily 01:17 UTC: restarts tasks still on Aurora's pre-rotation password

ci-templates/monorepo/           # Copy into the service monorepo's .github/workflows/
                                  # (build-and-deploy.yml deploys via the ECS API directly)
```

<div align="center">

**Built for AWS Frankfurt · Multi-AZ · Serverless-first**

</div>
 