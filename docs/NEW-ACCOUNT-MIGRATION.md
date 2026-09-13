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
| ACM certificates + HTTPS listener | No `:443` at all; `:80` returns a 503 fixed-response | `request-certs.sh` → `configure-alb.sh` (step 14) |
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

Nothing further is needed here. The per-service Redpanda password ARNs used to be
literals in `env.hcl` and all 19 had to be read back out of AWS and substituted by
hand at this point — Secrets Manager appends a random six-character suffix, so an
ARN is valid in exactly one account. The `ecs-services` module now resolves them by
**name** instead (`binbon-<env>-redpanda-<redpanda_user>`, which is deterministic),
driven by `redpanda_secret_name_prefix`, so `env.hcl` carries no Secrets Manager
ARNs at all and this step no longer exists.

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

## 8. Confirm the per-service databases exist

Aurora is created with a single database (`app`), but the design is
database-per-service so each service's sqlx migration history stays independent.
The `secrets` component creates those 20 databases as part of its apply
(`terraform_data.service_database`, driven by `postgres_service_databases` — the
same map that composes each `DATABASE_URL`), so step 7 has already done this.

Verify rather than assume:

```bash
./scripts/db-bootstrap.sh    # read-only; lists required vs existing
```

Expect *"Nothing missing - every required database already exists."*

> [!NOTE]
> This used to be a manual step, and forgetting it brought up a fresh account
> with **20 crash-looping services** reporting `database "binbon_x" does not
> exist` — with nothing in the codebase indicating the step existed. It is now
> in Terraform; `db-bootstrap.sh` is kept as a diagnostic and as a way to create
> the databases without a full apply.

Creation goes over the RDS Data API (`enable_http_endpoint = true`), so no VPN or
private-subnet access is needed — but it does mean **the AWS CLI must be present
wherever `terragrunt apply` runs**. Set `create_service_databases = false` to opt
out.

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

## 13. Check the VPN actually serves

`terragrunt apply` reports a healthy EC2 instance whether or not OpenVPN is
running, so verify rather than assume:

```bash
./scripts/vpn-check.sh dev
```

Since the `user_data` bootstrap was added the instance self-configures on first
boot — it runs `ovpn-init`, enables the service, and widens the advertised
private network to the whole VPC. Instances built **before** that change come up
dormant: SSH answers on 22 while 443/943/1194 refuse, because `config.db` was
never created.

To recover a dormant instance without a key pair, use **EC2 Instance Connect**
(the instance profile also allows SSM Session Manager):

```bash
aws ec2-instance-connect send-ssh-public-key --instance-id <id> \
  --instance-os-user root --ssh-public-key file://key.pub \
  --availability-zone <az> --region eu-central-1
# then, on the host:
/usr/local/openvpn_as/bin/ovpn-init --batch --local_auth --host=<public-ip>
systemctl enable --now openvpnas
```

> [!WARNING]
> `--batch` constitutes acceptance of the OpenVPN Access Server EULA. That is the
> account owner's decision to make, not something to automate on their behalf
> without asking.

Set an admin password and store it rather than leaving the installer's:

```bash
/usr/local/openvpn_as/scripts/sacli --user openvpn --new_pass '<pw>' SetLocalPassword
/usr/local/openvpn_as/scripts/sacli --user openvpn --key prop_superuser --value true UserPropPut
```

Keep it in Secrets Manager as `binbon-<env>-vpn-admin`.

### If the VPN connects but nothing behind it responds

`ovpn-init` advertises the server's **own subnet** as the private network — a
`/20` here. Clients then get a route to the VPN's subnet and nothing else, so
Aurora, Redis and OpenSearch in the other `/20`s time out. It reads like a
firewall problem and is not:

```bash
sacli ConfigQuery | grep private_network   # expect the VPC /16, not a /20
sacli --key "vpn.server.routing.private_network.0" --value "10.20.0.0/16" ConfigPut
sacli start
```

Clients must **reconnect** — routes are pushed at connection time.

---

## 14. HTTPS: certificates and the ALB

Terraform does not own this, and deliberately so. ACM DNS validation needs
records added at an external registrar (there is no Route 53 zone), so an apply
would block indefinitely waiting for a human. `env.hcl` therefore keeps
`alb_certificate_arn = null`, and with it null the `alb` module builds:

| listener | what Terraform creates |
|---|---|
| `:80` | HTTP, default action = **`fixed-response 503`** |
| `:443` | **not created at all** |

Two scripts turn that into a working HTTPS front end. Run them in order, after
the infrastructure exists.

### 14a. Request the certificates

```bash
./scripts/request-certs.sh
```

It asks how many certificates you want and for each exact domain, then prints
per certificate: **domain, status, ARN, CNAME name, CNAME value**. Add those
CNAMEs at your DNS provider; ACM validates within minutes of them resolving.
Re-run (or use `--wait`) until every certificate is `ISSUED` — the script exits
non-zero while any are pending, so it is safe to chain.

> [!IMPORTANT]
> A wildcard matches exactly **one** label. `*.binbon.ch` covers
> `dev.binbon.ch` but **not** `api.dev.binbon.ch`. Serving a host two levels
> deep needs either `*.dev.binbon.ch` or that exact hostname — otherwise the
> browser shows "not secure" on a name mismatch, with a perfectly valid
> certificate for the wrong name.

> [!NOTE]
> Keep the validation CNAMEs in DNS permanently. ACM re-checks them at renewal,
> so deleting them after issuance breaks auto-renewal about 13 months later.

### 14b. Configure the ALB

```bash
./scripts/configure-alb.sh \
    --default-cert <arn> \
    --sni-cert     <arn>
```

`request-certs.sh` prints this command with the ARNs already filled in. The
script is idempotent and supports `--dry-run`. It sets:

- `:443` HTTPS with the default certificate, TLS policy, and a default forward
  to the api-gateway target group
- the second certificate attached over **SNI** (an ALB serves several)
- a `/api/*` rule at priority 2 forwarding to api-gateway
- `:80` redirecting **301** to HTTPS

> [!WARNING]
> These changes are invisible to Terraform. Running `terragrunt apply` on the
> `alb` component afterwards reverts `:80` to the 503 fixed-response and leaves
> `:443` orphaned. **Re-run `configure-alb.sh` after any `alb` apply.**

### Verifying

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://<host>/health   # expect 200
```

`/health` is served by api-gateway itself and is the only endpoint reachable
from a browser address bar. Application routes live under `/api/v1/...` and are
mostly POST-only, so a `404` or `405` from a browser is normal and is not an ALB
fault. Tell the layers apart by the response body: the gateway returns its own
JSON envelope (`{"error":{"code":"NOT_FOUND",...}}`), an upstream service
returns an empty-bodied 404, and a genuine ALB failure is a raw 502/503.

---

## 15. Keeping up with password rotation

Aurora's master password is RDS-managed and rotates on a schedule (7 days by
default). Two separate things break if nothing handles it:

**The composed URL goes stale.** Historically the `secrets` component baked the
password into each `DATABASE_URL` at apply time, so every rotation required
re-applying `secrets` and redeploying. That is fixed: services now receive
`DB_HOST`/`DB_PORT`/`DB_NAME` plus `DB_USER`/`DB_PASSWORD` wired straight to the
RDS-managed secret, and `shared::config::database_url` composes the URL in-process.
ECS resolves those at task start, so a rotation needs **no Terraform apply**.

**Running tasks keep the old password.** ECS injects secrets only at task start.
Existing pooled connections survive a rotation — Postgres does not drop live
sessions — but every new connection fails with `password authentication failed`.
This is silent: the HTTP listener is unaffected, the health check passes, and the
service reports healthy while background work that opens fresh connections (the
outbox relay, pool growth) fails continuously.

`.github/workflows/rotation-restart.yml` closes that gap. It runs daily and
restarts only the services whose task predates the last rotation:

```bash
./scripts/restart-stale-db-tasks.sh          # report
./scripts/restart-stale-db-tasks.sh --apply  # restart the stale ones
```

> [!NOTE]
> It is condition-driven, not date-driven, on purpose. AWS rotates within a
> window rather than at a fixed interval — one observed gap was 7d17h, not 7d —
> so a schedule pinned to the expected rotation day drifts and eventually fires
> *before* the rotation it was meant to follow. Running daily is a no-op on quiet
> days and self-heals after an off-cycle or manual rotation.

The script reports each service's password source and refuses to pretend a
restart helps one that still has a pre-composed `DATABASE_URL` — restarting such
a task just restarts it into the same stale value.

---

## 16. Applying from CI instead of a workstation

`.github/workflows/terraform-apply.yml` (manual dispatch: environment, stack,
plan/apply) builds the whole stack with `stack = all`, `action = apply`.

**Prerequisites**

| | |
|---|---|
| IAM role | `binbon-github-terraform-apply` — created by `terragrunt/github-oidc` |
| Repo variable | `AWS_TERRAFORM_APPLY_ROLE_ARN` must hold that role's ARN |

Without the variable the workflow fails at the credentials step.

**What it still cannot do**, and why:

1. **`terragrunt/bootstrap`** — it keeps **local** state, which a runner discards.
   Apply it from a workstation once per account before using this workflow.
2. **The OpenVPN AMI Marketplace subscription** — AWS exposes no API to accept
   Marketplace terms.
3. **`scripts/request-certs.sh`** — ACM DNS validation needs records at an
   external registrar, so an apply would block indefinitely.
4. **`scripts/configure-alb.sh`** — depends on (3).

Everything else, including the per-service databases, runs in the workflow.

> [!IMPORTANT]
> Terragrunt v1 replaced `run-all <cmd>` with `run --all -- <cmd>`. The old
> spelling is not a valid command and exits with generic usage text rather than
> an obvious error, which reads like the workflow did nothing.

A full apply into a **fresh** account fails once on the OpenSearch service-linked
role (see step 7); the workflow retries automatically for `stack = all` +
`apply`, since that failed call is what makes AWS create the role.

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
