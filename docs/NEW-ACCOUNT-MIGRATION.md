# Migrating the platform to a new AWS account

A step-by-step runbook for standing this stack up in a fresh AWS account, written
from two actual migrations rather than from the design docs: `995192978674` →
`803817915623`, then `803817915623` → `922640336342` (with new Redpanda and
ClickHouse organizations), both in `eu-central-1`. Every step that bit us in practice is called
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
| ACM certificates | No `:443` at all; `:80` returns a 503 fixed-response | `request-certs.sh`, then the ARNs in `env.hcl` (step 14) |
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

### New-account limits

A brand-new AWS account has two limits that stop this stack. Raise both on
day one, because AWS can take a day or more to act on either.

| limit | symptom | fix |
|---|---|---|
| **Fargate On-Demand vCPU**, 6 by default | only 12 of the 31 services (0.5 vCPU each) can run; a full-fleet deploy needs about 31 | Service Quotas → AWS Fargate → `L-3032A538`; ask for 64 |
| **CloudFront** is off until AWS verifies the account | `media` fails: *"Your account must be verified before you can add new CloudFront resources"* | a Support case (Account and billing), quoting the error |

```bash
aws service-quotas request-service-quota-increase --service-code fargate \
  --quota-code L-3032A538 --desired-value 64 --region eu-central-1
```

If dev has to run before AWS answers, dev's `env.hcl` has a TEMPORARY switch
for each:

- `media_cloudfront_enabled = false` builds `media` without its distribution.
  `secrets` then writes an empty `CDN_BASE_URL`, and the services serve
  presigned S3 URLs. Without it, `secrets` and `services` can't apply,
  because `secrets` reads media's CloudFront address.
- `cpu = 256` per service fits all 31 in 7.75 vCPU, with room for one
  deployment at a time.

Undo both once the limits lift.

### New Redpanda and ClickHouse organizations

Signing up creates sample resources. Delete them before the first apply:

- **ClickHouse** creates a service named after the organization. If that name
  matches `binbon-<env>` in any case, the apply fails with
  `409 DUPLICATE_INSTANCE_NAME`, because ClickHouse names ignore case.
- **Redpanda** creates a `welcome` serverless cluster and a `default` resource
  group. They don't conflict, but the cluster uses trial credit.

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

## 4. Point `backend.hcl` at the new account

The account and its state backend live in **one file**,
`terragrunt/backend.hcl`. Every component and `github-oidc` read it with
`find_in_parent_folders("backend.hcl")`:

```hcl
locals {
  account_id   = "<new account id>"
  state_bucket = "<state_bucket output from step 3>"
  lock_table   = "binbon-bootstrap-tf-lock"
  state_region = "eu-central-1"
}
```

`account_id` does three jobs:

- it builds the ECR image URIs: `env.hcl` holds only `binbon-<env>:<service>-replace`,
  and `services.hcl` adds the registry;
- it sets Redpanda's PrivateLink principal;
- it sets `allowed_account_ids` on every generated AWS provider. A shell
  pointed at the **wrong** account then fails at plan time instead of
  building there.

The first two migrations had to rewrite the bucket name in 18 files and the
account ID in `env.hcl` 33 times, by `sed`. That's gone.

Then **clear the Terragrunt caches**, or the old backend config is reused and you
get confusing "bucket does not exist" failures:

```bash
find terragrunt -type d -name '.terragrunt-cache' -prune   -not -path 'terragrunt/bootstrap/*' -exec rm -rf {} +
```

> [!CAUTION]
> Leave `terragrunt/bootstrap`'s cache alone. Bootstrap keeps **local** state,
> and its `terraform.tfstate` lives inside that cache. It's the new backend's
> only state. Copy it to `bootstrap-new-account-<id>.tfstate` at the repo root
> first (`*.tfstate` is gitignored).

An environment that lives in a different account can carry its own
`terragrunt/envs/<env>/backend.hcl`; the nearest file wins.

---

## 5. Reset what belongs to the old account in `env.hcl`

`env.hcl` no longer holds the account ID. Three things in it still belong to
the old account. Set them before the first apply:

| setting | set it to | why |
|---|---|---|
| `alb_certificate_arn`, `alb_additional_certificate_arns` | `null` and `[]` | Certificates exist in one account only. With the old ARNs, the `alb` apply **fails**. Step 14 sets the new ones. |
| `media_cloudfront_enabled` (TEMPORARY) | `true` if the account can create CloudFront resources, else `false` | see *New-account limits* |
| service `cpu` (TEMPORARY) | `512` if the Fargate quota allows it, else `256` | see *New-account limits* |

Then confirm nothing in the tree still names the old account:

```bash
grep -rn '<old-account-id>' terragrunt/ --include='*.hcl' | grep -v terragrunt-cache
```

---

## 6. Populate Secrets Manager

Export the credentials from step 1, then run the bootstrap. It creates ~27
secrets. It generates the three platform-wide ones (`JWT_SECRET`,
`INTERNAL_API_KEY` and media-service's `MEDIA_URL_SIGNING_KEY`) and one
`REDPANDA_SASL_PASSWORD` per service.

**Run it before the first `secrets` apply.** `components/secrets.hcl` reads the
three platform-wide secrets back into the shared `infra-secrets` JSON, so the
`secrets` plan fails if one doesn't exist. On an account bootstrapped before
`MEDIA_URL_SIGNING_KEY` existed, re-run the script once: it creates only that
secret.

```bash
export AWS_PROFILE=<new-account-profile>
export ENVIRONMENT=dev REGION=eu-central-1
export REDPANDA_CLIENT_ID=... REDPANDA_CLIENT_SECRET=...
export CLICKHOUSE_ORG_ID=... CLICKHOUSE_CLOUD_API_KEY=... CLICKHOUSE_CLOUD_API_SECRET=...
./scripts/bootstrap-secrets.sh
```

Anything not exported is prompted for interactively; a blank value is refused
rather than silently stored.

**It's safe to re-run.** By default it only *creates* secrets that don't exist
yet; an existing secret is left exactly as it is and reported. That makes
re-running the way to add a secret for a **new service** on an existing account:
add the name to the script's `SERVICES` list and run it again. It creates just
that one, and doesn't prompt for API credentials whose secrets already exist.

```
created: 1   left untouched: 26   rotated: 0
```

It fails loudly, rather than silently falling back to an update, if a secret is
**scheduled for deletion** — common when re-bootstrapping soon after a teardown.
Restore the secret or wait for the deletion to finish.

> [!CAUTION]
> **`--force` overwrites existing secrets — and on a serving account, that is an
> outage until you finish the rotation by hand.**
>
> | secret | what breaks, and what finishes the rotation |
> |---|---|
> | 20 `binbon-<env>-redpanda-<service>` | Users are set with `password_wo` and a static `password_wo_version`, so the new value never reaches Redpanda and **every Kafka service fails authentication**. Bump those users' `password_wo_version` in `env.hcl`, apply `redpanda`, redeploy. |
> | ClickHouse admin password | The same write-only mechanism; analytics can't connect. Bump the clickhouse `password_wo_version`, apply `clickhouse`, redeploy. |
> | `JWT_SECRET` | Every issued token stops validating — **every user is logged out**. |
> | `INTERNAL_API_KEY` | Internal calls fail until every service has redeployed. |
> | `MEDIA_URL_SIGNING_KEY` | Signed media (HLS) URLs already handed out stop verifying. |
>
> Because of that, `--force` shows this list, **requires typing the environment
> prefix** (`binbon-dev`) to continue, and refuses to run without a terminal — it
> is not something to do unattended or from CI. Typing the wrong environment
> aborts with nothing changed. When it does rotate, it prints the follow-up.
>
> The script used to behave like `--force` on every run. That is why this
> caution exists.

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
Run it where nothing will cut it short. OpenSearch alone took 14 minutes in
the reference migration.

### If an apply is interrupted

Killing an apply mid-run leaves two kinds of mess, and both need clearing
before the next run:

1. **Stale state locks.** List them, confirm no `terraform` process is still
   running, then release each one:
   ```bash
   aws dynamodb scan --table-name binbon-bootstrap-tf-lock \
     --query 'Items[?Info!=`null`].Info.S' --output text
   ./scripts/tg.sh <component> force-unlock -force <ID from Info>
   ```
2. **Resources that exist but aren't in state.** Anything still being created
   when the run died is there in AWS or Redpanda, but the state doesn't know
   about it. The next apply then fails with *already exists*. Import each one
   rather than deleting it:
   ```bash
   ./scripts/tg.sh data import 'aws_keyspaces_table.this["<table>"]' <keyspace>/<table>
   ./scripts/tg.sh redpanda import redpanda_resource_group.this <id>
   ./scripts/tg.sh redpanda import 'redpanda_topic.this["<topic>"]' '<topic>,<cluster id>'
   ```
   Compare each component's `state list` with what exists to find them.

Redpanda's data plane sometimes drops a `CreateTopic` with *"the broker
connection has died"*. The retry usually goes through anyway, so the next
apply reports the topic *already exists*. Import it the same way.

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
| `vars.AWS_ECS_DEPLOY_ROLE_ARN` | `ecs_deploy_role_arn` from step 9 |

The deploy signs in through GitHub OIDC: it assumes `binbon-github-ecs-deploy`
for two hours, and no AWS keys are stored in GitHub. Delete any leftover
`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` repository secrets — nothing reads
them, and keys for a new account are often its root keys, which must never be
stored there.

In **this** repo, set `vars.AWS_TERRAFORM_APPLY_ROLE_ARN` to
`terraform_apply_role_arn` from step 9 (see step 16).

Branch routing in the deployed workflow is `dev → dev`, `staging → staging`,
`master → prod`.

Then build and deploy real images. Until this happens every task definition
points at the non-existent `binbon-dev:<service>-replace` placeholder.

**A push is not enough for the first deploy.** On a push the workflow deploys
only the services whose directories changed. Every other service stays on the
placeholder. Dispatch it once for the whole fleet instead:

```bash
gh workflow run build-and-deploy.yml --ref dev -f environment=dev -f service=all
```

The fleet deploys in parallel. That's fine the first time, when nothing is
running yet, but at a low Fargate quota (see *New-account limits*), later
redeploys have to go one service at a time.

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

**What `HEALTHY` proves about Kafka.** For the 19 services that set
`HEALTH_REQUIRES_KAFKA` (see step 17), ECS `HEALTHY` now means the service
**reached the broker and authenticated at least once**: `/health` returns 503
until it has. A fresh account with wrong or missing Redpanda credentials
therefore shows up here as services that never go healthy and deployments that
roll back, rather than as a green fleet that silently can't publish.

> [!WARNING]
> `HEALTHY` still does **not** prove the per-topic ACLs are right. A service that
> authenticates but lacks READ or WRITE on one of its topics connects fine,
> passes the check, and then fails with `TopicAuthorizationFailed` — silently,
> because its consumer just retries. recommendation-service ran like that at
> ~6,700 errors an hour with a healthy status. Check for it directly:
>
> ```bash
> ./scripts/kafka-check.sh dev 30    # TopicAuthorizationFailed, SASL errors
> ```
>
> Before a deploy, the consistency check in step 17 catches the same class of
> problem from the code.
>
> api-gateway and the 11 services that don't use Kafka are not gated, so their
> `HEALTHY` says nothing about the broker. Consumer-group lag is no help either:
> rskafka reads partitions directly rather than joining a Kafka consumer group.

> [!WARNING]
> `HEALTHY` doesn't prove the **Keyspaces tables** exist either. A feature whose
> table is missing keeps its gate closed and answers 503, and on purpose that is
> not a startup failure. chat-service deployed healthy while every message send
> was a 503. Search the logs for closed gates directly:
>
> ```bash
> aws logs filter-log-events --log-group-name /ecs/binbon-dev/chat-service \
>   --filter-pattern '"feature unavailable"' --start-time $(( ($(date +%s) - 900) * 1000 ))
> ```
>
> Each line names the feature and the missing table or option. Step 18 covers
> the fix and the pre-merge check.

> [!WARNING]
> `HEALTHY` doesn't prove a service got its **config** either. Many variables
> fall back to a dev value when unset, and the service starts normally:
>
> - 10 services never got `INTERNAL_API_KEY` and used the placeholder compiled
>   into the source. notification-service, which had the real key, got 401 from
>   user-service for hours.
> - auth-service never got `NOTIFICATION_INTERNAL_URL`, so every OTP went to
>   `localhost` and the verify request failed closed.
>
> Look for them directly:
>
> ```bash
> aws logs filter-log-events --log-group-name /ecs/binbon-dev/notification-service \
>   --filter-pattern '?"INTERNAL_API_KEY differs" ?"is not configured"' \
>   --start-time $(( ($(date +%s) - 3600) * 1000 ))
> ```
>
> Step 19 covers the pre-merge check.

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

### Logins: `scripts/vpn-user.sh`

The installer leaves the `openvpn` admin with a random password nobody knows,
and no other logins. `vpn-user.sh` manages them without anyone logging in to
the host:

```bash
./scripts/vpn-user.sh admin-password        # admin UI: https://<vpn-ip>:943/admin
./scripts/vpn-user.sh add <user>            # one login per person
./scripts/vpn-user.sh password <user>       # print it, to hand on privately
./scripts/vpn-user.sh profile <user>        # save <user>.ovpn for OpenVPN Connect
./scripts/vpn-user.sh remove <user>         # revoke certs, delete login and secret
./scripts/vpn-user.sh list | info           # logins; address and routes
```

Each password is generated locally and kept in Secrets Manager
(`binbon-<env>-vpn-admin`, `binbon-<env>-vpn-user-<name>`). The script drives
the host over SSM, and the command carries only the secret's **name**. The
host reads the value itself (its role may read `binbon-<env>-vpn-*`, nothing
else), so no password lands in SSM's command history.

To connect, use **OpenVPN Connect**: either Import Profile → URL →
`https://<vpn-ip>` and log in, or import the `.ovpn` from `profile`. That
file holds the user's certificate and key, so `*.ovpn` is gitignored. The VPN
is a split tunnel: only `10.20.0.0/16` goes through it.

> [!NOTE]
> `remove` schedules the secret's deletion with a 7-day recovery window. Re-adding
> the same name within those days fails until you restore the secret
> (`aws secretsmanager restore-secret`) or the window passes.

### Reaching the databases (pgAdmin and other tools)

Access Server passes client traffic on as **the VPN instance**
(`vpn.server.routing.private_access = "nat"`). So a private service only
answers VPN clients if its security group admits `binbon-<env>-vpn`. The `vpn`
component lists what VPN clients may reach in `reachable_ports`, and each entry
becomes one ingress rule:

```hcl
reachable_ports = { postgres = { security_group_id = dependency.data.outputs.security_group_id, port = 5432 } }
```

Dev opens **Aurora on 5432** only. Redis (6379 on the same `data` group) or
OpenSearch (443 on its own group) would each be one more entry.

To connect pgAdmin, first connect the VPN, then register a server:

| field | value |
|---|---|
| Host | the cluster endpoint, `binbon-<env>-aurora.cluster-<id>.<region>.rds.amazonaws.com` (`cluster-ro-…` for read-only queries) |
| Port / maintenance DB | `5432` / `app` |
| Username | `platformadmin` (the master user) |
| Password | `aws secretsmanager get-secret-value --secret-id '<rds!cluster-… secret>' --query SecretString --output text`, the `password` field. The ARN is the cluster's `MasterUserSecret`. |
| SSL mode | **`require`**: the cluster has `rds.force_ssl = 1` and refuses plain connections |

There is one database per service (`binbon_auth`, `binbon_wallet`, …, 19 in
all), plus `app`.

> [!WARNING]
> The master password **rotates about every 7 days** (step 15). The services
> follow it on their own, but a password saved in pgAdmin stops working. When
> pgAdmin reports *password authentication failed*, read the secret again.
> `platformadmin` can change or drop anything in every service's database. A
> separate read-only role for developers, with its own secret, would be safer
> to hand out.

### If the VPN connects but nothing behind it responds

There are two causes, and both look like a firewall problem.

**The service's security group doesn't admit the VPN.** A connection times
out even though the route is right. The service needs an entry in
`reachable_ports` (above). Before that existed, the `data` group admitted 5432
only from the tasks, so pgAdmin over the VPN could never connect.

**The VPN advertises too small a network.**

`ovpn-init` advertises the server's **own subnet** as the private network, a
`/20` here. Clients then get a route to the VPN's subnet and nothing else, so
Aurora, Redis and OpenSearch in the other `/20`s time out. The first-boot
script now widens it to the VPC; `./scripts/vpn-user.sh info` shows what's
advertised. To fix it by hand:

```bash
sacli ConfigQuery | grep private_network   # expect the VPC /16, not a /20
sacli --key "vpn.server.routing.private_network.0" --value "10.20.0.0/16" ConfigPut
sacli start
```

Clients must **reconnect** — routes are pushed at connection time.

---

## 14. HTTPS: certificates and the ALB

The **certificates** stay outside Terraform: ACM DNS validation needs records
added at an external registrar (there is no Route 53 zone), so an apply would
block indefinitely waiting for a human. The **listeners** are Terraform's. Until
`alb_certificate_arn` is set, the `alb` module builds:

| listener | what Terraform creates |
|---|---|
| `:80` | HTTP, default action = **`fixed-response 503`** |
| `:443` | **not created at all** |

So: request the certificates (14a), then hand their ARNs to Terraform (14b).

### 14a. Request the certificates

```bash
./scripts/request-certs.sh                                    # prompts
./scripts/request-certs.sh --domain '*.dev.binbon.ch'
```

Dev uses **one** certificate, `*.dev.binbon.ch`. It covers every host on the
ALB: `api.dev.binbon.ch` and `api-gateway.dev.binbon.ch`. (It used to be
`api.dev.binbon.ch` plus `*.binbon.ch`, and neither covered
`api-gateway.dev.binbon.ch`.) Certificates belong to one account, so a new account
requests them again, with **new** validation CNAMEs. Delete the old account's
records.

Without `--domain`, it asks how many certificates you want and for each exact
domain. Either way it prints
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

Also point each served host at the **new** ALB. Dev has two `CNAME`s,
`api-gateway.dev.binbon.ch` and `api.dev.binbon.ch`, both →
`binbon-dev-alb-<id>.eu-central-1.elb.amazonaws.com`. The ALB's DNS name
changes with every account, so update or delete every record that still names
the old one, along with the old account's validation CNAMEs. Those are the
`…acm-validations.aws` values that match no certificate in the new account.

### 14b. Hand the certificates to Terraform

Once every certificate is `ISSUED`, `request-certs.sh` prints the two lines for
`env.hcl` (null until now, see step 5):

```hcl
alb_certificate_arn             = "<*.dev.binbon.ch arn>"
alb_additional_certificate_arns = []   # more certificates, by SNI, only if a host needs one
```

Then apply `alb`, then `services`:

```bash
./scripts/tg.sh alb apply
./scripts/tg.sh services apply
```

| | |
|---|---|
| `:443` | HTTPS, the default certificate plus the others over **SNI**, TLS policy `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09`; default action 404 |
| `:80` | **301** to HTTPS for every path |
| api-gateway's rule | moves to `:443` with `services`, for `/api/*` and `/health` |

`services` has to follow `alb`. The `/api/*` rule attaches to the `alb`
component's `listener_arn` output, which is `:443` once a certificate is set and
`:80` until then.

> [!CAUTION]
> This used to be `scripts/configure-alb.sh`, which built `:443` outside
> Terraform. It left a hole: the `/api/*` rule stayed on `:80`, so API calls
> over `http://` were **served unencrypted instead of redirected**, tokens
> included. An `alb` apply also reverted `:80` to the 503. The script is gone.
> If an account still has a hand-made `:443` listener, import it rather than
> deleting it, and nothing goes down:
>
> ```bash
> ./scripts/tg.sh alb import 'aws_lb_listener.https[0]' <listener arn>
> ./scripts/tg.sh alb import 'aws_lb_listener_certificate.additional["<cert arn>"]' '<listener arn>_<cert arn>'
> ```
>
> Then apply `alb` and `services`, and delete the script's leftover priority-2
> `/api/*` rule on `:443`.

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

### Giving developers access

| | |
|---|---|
| Base URL | `https://api-gateway.dev.binbon.ch` (routes under `/api/v1/...`) |
| Postman | `qa/binbon.postman_collection.json` in the backend repo, with `base_url`, `media_url`, `comment_url`, `story_url` and `presence_url` set to the base URL. The gateway routes those public paths. |
| Login | OTP, with dev's fixed code (step 20). Share it privately. |

What they can't reach from outside, by design or not yet:

- `/internal/...` endpoints, which are service-to-service only;
- chat's and live's WebSockets: the gateway doesn't proxy them, and only
  api-gateway sits behind the ALB;
- CloudFront media links, until the account is verified (presigned S3 links
  are used meanwhile).

The WAF in front (see *Post-migration notes*) returns 403 to requests without
a `User-Agent`, and past 2000 requests per IP per 5 minutes. A whole team
running the full collection from one office IP can hit that.

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
   external registrar, so an apply would block indefinitely. Once the
   certificates are issued and their ARNs are in `env.hcl`, the workflow
   applies the HTTPS listener like anything else.

Everything else, including the per-service databases, runs in the workflow.

> [!IMPORTANT]
> Terragrunt v1 replaced `run-all <cmd>` with `run --all -- <cmd>`. The old
> spelling is not a valid command and exits with generic usage text rather than
> an obvious error, which reads like the workflow did nothing.

A full apply into a **fresh** account fails once on the OpenSearch service-linked
role (see step 7); the workflow retries automatically for `stack = all` +
`apply`, since that failed call is what makes AWS create the role.

---

## 17. Kafka topic and ACL consistency

The backend and this infra live in separate repositories, and every Kafka topic
the code uses has to exist here, with a Redpanda user for the service and an
ACL for the direction it uses it in. Nothing used to link the two, so they
drifted silently. A messaging change made chat-service a Kafka client; the infra
never gave it a Redpanda account; it deployed as healthy while every message
send returned 503. Two guards now stop that, one before merge and one at deploy.

### 17a. Before merge — the consistency check

`kafka-infra-check.yml` in the **backend** repo runs
`scripts/check-kafka-infra.py` on every push to `dev` and every pull request to
`dev`, `staging` and `master`. For each service that touches Kafka, it fails if:

| gap | example message |
|---|---|
| a topic isn't declared | `chat-service uses topic 'message.events', which is not declared in dev env.hcl` |
| no Redpanda user | `chat-service uses Kafka but has no Redpanda user in service_users` |
| user not wired to the service | `... redpanda_user = None, so the task gets no REDPANDA_SASL_* credentials` |
| missing WRITE | `chat-service produces to 'moderation.events' but has no WRITE ACL on it` |
| missing READ | `recommendation-service consumes 'post.events' but has no READ ACL on it` |

It reads `env.hcl` from this repo's `main` branch. **So for new Kafka work the
order is infra first, then backend**: add the topic, user and ACLs here, merge,
and only then does the backend PR pass. It's the same ordering any schema or
credential change needs.

Run it locally from the backend repo, pointing `--infra` at your checkout of
this one (whatever its directory is called locally):

```bash
python3 scripts/check-kafka-infra.py --infra ../binbon-aws-terraform-complete --env dev
```

> [!NOTE]
> Topic use is inferred from the code, and the rules are deliberately narrow —
> emit, outbox and publish calls for producers; consumer entry points, consumer
> tables and consumer modules for consumers; test modules ignored. A broader
> "any mention of a topic" rule was tried first and granted permissions wrong in
> both directions. If it ever flags something that isn't real, fix the rule in
> the script rather than granting the permission.

#### The fix opens itself: automatic infra pull requests

On a **push to `dev`**, a failing check doesn't stop at reporting. It runs
`check-kafka-infra.py --fix` against this repo's `main`, which writes the
missing **topics** (2 partitions, delete, 7 days, like every `.events` topic
here) and **ACLs** (the READ or WRITE, plus DESCRIBE) into dev's `env.hcl`. It
then opens a pull request here on an `auto/kafka-<sha>` branch, and the PR body
lists exactly what it adds. From there:

1. `kafka-apply.yml` (this repo) runs a `redpanda` **plan** on the pull
   request, so the review is of real topics and ACLs.
2. **Merge it**, and the same workflow **applies** `redpanda`.
3. Re-run the backend's Kafka check, and it passes.

A developer's new topic or permission therefore costs one review and merge.
Two cases still need a person, and the PR says so:

- a service with **no Redpanda user** at all needs a password secret
  (`bootstrap-secrets.sh`) and `redpanda_user` wiring;
- a **user that isn't wired** to its ECS service.

While one automatic PR is open, later pushes don't open another; merge it and
re-run. The fix was tested on a copy of `env.hcl` with a topic and two ACLs
removed: it restored all three, the result was valid HCL, and the check went
from 5 gaps to 0.

It needs a second secret on the backend repo, **`INFRA_PR_TOKEN`**: a
fine-grained token (or, better, a GitHub App) on `binbon-infra` with
**Contents** and **Pull requests** read/write. Without it, the check fails as
before and warns that no PR was opened.

#### The token it needs

The check runs in the backend repo but reads this one, which is private, and a
workflow's built-in token can only see its own repository. It uses a repository
secret on `official-backend-rust`, which the Keyspaces (step 18) and service
config (step 19) checks share:

| | |
|---|---|
| Secret | `INFRA_REPO_TOKEN` |
| Type | fine-grained personal access token |
| Resource owner | `BINBON-app` |
| Repository access | only `binbon-infra` |
| Permission | **Contents: Read-only** |

Without the secret, the job fails straight away with setup instructions instead
of quietly skipping.

> [!WARNING]
> GitHub's error for a token that lacks **Contents** is misleading:
> `remote: Write access to repository not granted` with a **403**, even though the
> check only reads. *Metadata: Read-only* is added automatically, and that lets
> the token see the repo exists but not read its files — so it looks configured
> when it isn't. A **404** instead means the token can't see the repo at all:
> wrong resource owner or wrong repository selected. If the org requires approval
> for fine-grained tokens, a pending token fails the same way until an owner
> approves it.

The token belongs to whoever created it, so it **expires**, and it stops
working if they leave the org. When it expires, the checkout step fails with the
same 403 — renew the token, don't hunt for a gap. An org-owned GitHub App or
machine user removes that dependency; it's the better long-term setup.

This secret lives on the backend repo, not the AWS account, so moving to a new
AWS account doesn't touch it. Recreate it only if the repositories move to a
different GitHub org.

### 17b. At deploy — the startup health gate

The 19 services that open a broker connection at startup get
`HEALTH_REQUIRES_KAFKA=true` from `kafka_health_services` in
`terragrunt/components/services.hcl`. With it set, `/health` returns **503
`starting`** until the process has connected to the broker at least once, and
`/readyz` reports Kafka as required until then.

A misconfigured service — no credentials, wrong credentials, no route — never
connects, so it never passes the ECS health check. The circuit breaker rolls the
deployment back, and the deploy fails in CI instead of going green.

**Only the first connection matters.** A broker blip after a service has
connected keeps `/health` at 200. The ECS health check has *kill* semantics:
failing it on a Redpanda restart would recycle the whole fleet and turn a broker
hiccup into an outage.

> [!IMPORTANT]
> **During a migration this is the step most likely to surprise you.** If
> Redpanda credentials or networking are wrong in the new account, all 19 gated
> services stay unhealthy and their deployments roll back. That's the gate doing
> its job. Fix the cause — re-check steps 6 and 7, and that `redpanda-endpoint`
> applied — rather than removing the flag.

`kafka_health_services` is an **explicit list** for a reason. api-gateway holds
Redpanda credentials but never connects, because it's a pure proxy. Gated, it
would report "never connected" forever and ECS would kill the gateway in a loop.
Only add a service after confirming it opens a connection at startup — a warm-up,
the outbox relay, or a consumer loop.

The safety net for the gate itself is the circuit breaker: **enabled, rollback
on, minimum healthy 100%**. ECS starts new tasks before stopping old ones and
rolls back if they fail, so a fault in the gate reverts a deploy rather than
dropping one. Don't loosen those settings while the gate is on.

To disable the gate for one service, remove it from `kafka_health_services` and
apply `services`. It takes effect on that service's next deploy.

## 18. Keyspaces table consistency

> [!IMPORTANT]
> **Today the services own every table.** chat, comment, engagement, feed and
> story each run `<service> provision` before they roll out. It's a one-off ECS
> task with the provisioner credential (CREATE and ALTER, no DROP). It creates
> missing tables, adds missing columns and options, and refuses key or type
> changes. All 90 tables were handed over from Terraform with
> `terragrunt state rm 'aws_keyspaces_table.this'`. Nothing in AWS changed,
> and `tables.json` is now `"tables": {}`. Terraform keeps only the keyspace.
>
> **Why the handover had to happen:** while Terraform still listed a table, a
> provision step adding a column left Terraform with a schema it didn't know.
> The next `data` apply would have **replaced the table, dropping its data**. A
> push that added 26 columns turned the Keyspaces check red for exactly that
> reason.
>
> The rest of this step describes the Terraform-owned path, which still applies
> to any crate that doesn't provision its own tables. `--emit` leaves
> self-provisioned tables out.

On Amazon Keyspaces the services start with `MIGRATE_ON_START=false`, so a
table the service doesn't provision itself has to be provisioned here. Those
tables are listed in **`terragrunt/keyspaces/tables.json`**, which
`components/data.hcl` reads for every environment. It's generated from the
backend code, so don't edit it by hand.

The table options matter as much as the columns. A table created without
`ttl`, without its `default_time_to_live`, or without `client_side_timestamps`
still PREPAREs. It then fails the service's capability probe, and that feature
stays at 503 for good.

This used to live inline in dev's `env.hcl`, as a hand copy of only each
service's *legacy* tables. 61 feature tables were never created (33 for chat,
24 for story and the 4 `event_outbox*` tables), and 5 existing tables lacked
the TTL their DDL declares. Staging and prod had no table list at all.

**To change the tables** (a backend PR adds a table, column or option):

```bash
# in the backend repo
python3 scripts/check-keyspaces-infra.py --emit > ../binbon-aws-terraform-complete/terragrunt/keyspaces/tables.json
# in this repo: review the diff, merge to main, then
cd terragrunt/envs/dev/eu-central-1/data && terragrunt plan   # expect adds / in-place only
```

The plan must show only **adds and in-place updates**. Adding columns,
TTL, a default TTL or client-side timestamps are all in-place. A **replace**
means a key changed, and a replace **drops the table and its data**; stop and
migrate by hand instead. Services pick new tables up without a redeploy: a
closed gate retries every 60 seconds.

> [!WARNING]
> `ttl` and `client_side_timestamps` are **one-way** on Keyspaces. Once
> enabled, they can't be turned off, so a mistaken enable can't be undone by
> reverting the JSON.

### The check

`keyspaces-infra-check.yml` in the **backend** repo runs
`scripts/check-keyspaces-infra.py` against this repo's `main`, with the same
triggers and the same `INFRA_REPO_TOKEN` as the Kafka check (step 17a). For
every table in a crate that depends on `scylla`, it fails if the table is
missing or differs in any of these:

- partition key;
- clustering key, including ASC/DESC;
- a column or its type;
- static columns;
- `default_time_to_live`;
- a needed `ttl`, when the table has a default TTL, is written `USING TTL`, or
  has a TTL probe;
- a needed `client_side_timestamps`, when the table is written `USING TIMESTAMP`.

It also fails if `data.hcl` stops reading the file. As with Kafka, **the order
is infra first**: regenerate, merge and apply here, then the backend PR passes.

```bash
python3 scripts/check-keyspaces-infra.py --infra ../binbon-aws-terraform-complete
```

> [!NOTE]
> Tables that are only *described* in docs and never created in code aren't
> required. `story_moderation` is one: the story docs say the platform spec
> owns its shape, and no statement uses it yet. Provision it when that code
> lands, and the check will require it from then on.

## 19. Service config consistency

Each service's environment and secrets are assembled here, in
`components/services.hcl` and `env.hcl`, while the code that reads them lives in
the backend. Nothing linked the two. The worst drift is a variable whose default
is a **dev fallback**: the service starts normally and quietly misbehaves.

- **`INTERNAL_API_KEY`:** 10 services never got it. They used the placeholder
  compiled into the source, so they could talk to each other but got 401 from
  the 12 services that had the real key.
- **`NOTIFICATION_INTERNAL_URL`:** auth-service never got it, so every OTP went
  to `localhost` and the verify request failed closed.
- **`MEDIA_URL_SIGNING_KEY`:** media-service never got it, so it signed HLS URLs
  with a key anyone could read in the source. In production that route would
  have answered 503 instead.

### Platform secrets by default

Every service except **api-gateway** gets the platform secrets
(`platform_secret_keys` in `components/services.hcl`): `INTERNAL_API_KEY`,
`JWT_SECRET`, `KAFKA_BROKERS` and `REDIS_URL`. A developer whose code starts
reading one of them needs no infra change. Missing `INTERNAL_API_KEY` was the
most common gap here, and it can't happen any more.

api-gateway is exempt (`platform_secret_exempt`): it faces the internet and is a
pure proxy that never touches a token. Specialised secrets (S3, Scylla,
ClickHouse, OpenSearch, `MEDIA_URL_SIGNING_KEY`) stay per service in
`service_secret_keys`, and the check below still catches one that's missing.

### The check

`service-config-check.yml` in the **backend** repo runs
`scripts/check-service-config.py` against this repo's `main`, with the same
triggers and the same `INFRA_REPO_TOKEN` as the other two checks (step 17a).
For each service it fails when the code reads a variable in a way where "unset"
is a crash or a silent fallback, and the infra doesn't set it:

| read in code | when unset |
|---|---|
| `require(K)` | startup error |
| `secret_or_dev(K, dev)` | silently uses the dev placeholder |
| `internal_secret(svc, K, dev)` | dev placeholder outside production; the features are disabled in production |
| `optional(K, default)` with a `DEV_*`, `"dev-…"` or `localhost` default | silently uses that default |
| `redis_url(..)`, `database_url(..)` | a local Redis or Postgres |

`optional_secret(K)` and `database_url_opt()` are **notes only**, because unset
there is a supported "feature off" state. The current notes are the places API,
link previews, GIFs and recommendation's database. Mode switches with a plain
default, such as `RTC_MODE="dev"`, are product choices and aren't flagged.

What the infra provides is worked out from the same sources `services.hcl`
merges:

- `env.hcl` `environment` and `secret_arns`;
- the Redpanda credentials when `redpanda_user` is set;
- the Keyspaces flags, `internal_service_urls` and `DB_*` for
  `postgres_service_databases`;
- `HEALTH_REQUIRES_KAFKA` and `service_secret_keys`, where `DATABASE_URL` is
  dropped;
- what the backend's deploy workflow adds (`ensure_env`).

That derivation was checked against the live dev task definitions and matched
all 31 services exactly.

**To fix a gap**, add the variable here, apply `services`, and redeploy the
service through the backend CI so its revision picks it up:

| the variable is… | put it in |
|---|---|
| a shared secret that already exists | that service's `service_secret_keys` entry |
| a URL of another service | `internal_service_urls`, as `http://<service>:<port>` (Service Connect) |
| plain config | the service's `environment` in `env.hcl` |
| a **new** generated secret | `bootstrap-secrets.sh`, then `components/secrets.hcl` and `modules/secrets`, then `service_secret_keys`. Re-run the bootstrap, then apply `secrets` and `services`. `MEDIA_URL_SIGNING_KEY` was added this way. |

```bash
python3 scripts/check-service-config.py --infra ../binbon-aws-terraform-complete --env dev
```

> [!NOTE]
> The deploy workflow allows only one pending run per environment, and a newer
> dispatch cancels an older one that's still queued. When several services
> need redeploying, dispatch them **one at a time** and wait for each to finish.

---

## 20. OTP and email delivery

auth-service issues OTPs and hands them to notification-service
(`/internal/notifications/message`), which delivers them through
`MESSAGE_TRANSPORT`. **Right now nothing is delivered on dev.** Two things were
in the way; the first is fixed.

1. **auth couldn't reach notification.** Without `NOTIFICATION_INTERNAL_URL`
   it used `http://localhost:8101`. Every OTP dispatch failed and the verify
   request failed closed (`otp.dispatch … failing closed`). It is now set in
   `internal_service_urls`, and step 19's check catches a regression.
2. **notification has no real transport.** No SMTP or SMS settings are
   configured, so it runs the default `log` transport, which only writes
   `would send to redacted recipient (log transport)`.

### Until email exists: the fixed code (dev only)

Dev's `env.hcl` sets `OTP_FIXED_CODE` on auth-service, so every OTP it issues
is that one code; the value is in `env.hcl`. Testers request a code as usual,
then type the fixed one.

- Only the issued code changes. Expiry, the five-attempt ceiling, the rate
  limits and the binding to the contact are untouched.
- auth **refuses to start** with it unless `APP_ENV` is explicitly `dev`,
  `development`, `local` or `test`, and logs `OTP_FIXED_CODE is set` at startup.
- Anyone who knows the code can verify any dev account.

> [!WARNING]
> Never copy `OTP_FIXED_CODE` to staging or prod `env.hcl`. auth would refuse
> to start there anyway, but the guard shouldn't be what catches it. Remove it
> from dev once real email is delivered.

### Real email through SES

**Infra:**

- **Sending identity:** an SES domain identity in Terraform. It outputs three
  DKIM CNAMEs; add SPF and DMARC too, so mail doesn't land in spam.
- **SMTP credentials:** an SMTP-only IAM user, restricted to sending from that
  domain. Its SMTP password is the access key's `ses_smtp_password_v4`. Put the
  pair into `infra-secrets` as `SMTP_USERNAME` / `SMTP_PASSWORD`; the key also
  ends up in the encrypted Terraform state.
- **notification-service:**
  - `MESSAGE_TRANSPORT=smtp,log`: email goes through SES, and SMS keeps `log`;
  - `SMTP_HOST=email-smtp.<region>.amazonaws.com`, `SMTP_PORT=587`,
    `SMTP_FROM`;
  - the two secrets added to its `service_secret_keys`.
- **Bounces and complaints:** an SES configuration set sending them to SNS.
  Recommended, and it helps a production-access request.
- **Network:** nothing to change. Tasks already reach the internet through the
  NAT gateway with unrestricted egress.
- **Finish:** apply `secrets` and `services`, redeploy notification one service
  at a time (step 19), then remove `OTP_FIXED_CODE`.

**Outside Terraform:**

- **Choose the sender domain.** The code's default is `binbon.app`, while the
  certificates are for `binbon.ch`.
- **Add the DNS records at the registrar.** There are no Route 53 zones, so
  this is manual, like ACM validation (step 14a).
- **Leave the SES sandbox.** New accounts only send to verified addresses, 200
  a day. Verify each tester's address, or request production access in the SES
  console (usually about a day).

**Code:**

- **Email needs no change.** The `smtp` transport already speaks STARTTLS on
  587 with login credentials, and bundles its own root certificates (lettre
  with `webpki-roots`).
- **SMS does need work.** The `http` transport POSTs `{to, from, body}` as JSON
  with one auth header. SNS (it needs SigV4) and Twilio (form-encoded, basic
  auth) don't accept that. Phone OTPs need a provider that takes that shape, an
  adapter (for example a Lambda calling SNS), or a new transport.
- **Production refuses `log`.** notification won't start with `log` in its
  transport list in production, so prod needs `smtp,http` with both wired.

---

## Post-migration notes

- **The API's WAF is on the ALB.** `waf-regional` is attached to the ALB:
  rate limit 2000 per IP per 5 minutes, AWS common rules, known bad inputs and
  IP reputation. There is no CloudFront in front of the API; the `edge`
  component was dropped. `SizeRestrictions_BODY` only counts, because
  multipart uploads over 8 KB go through api-gateway. Two things look like app
  bugs and aren't. A request **without a `User-Agent`** gets 403
  (`NoUserAgent_HEADER`). User text containing script tags or file paths can
  get 403 from the XSS and LFI body rules. Check the web ACL's sampled
  requests before debugging the service.
- **The deploy signs in through OIDC.** The backend's deploy assumes
  `binbon-github-ecs-deploy` for two hours, so no AWS keys are stored in
  GitHub (step 10). The role has to allow every call the workflow makes. It
  lacked `ecr:DescribeImages` until the switch, which would have failed every
  deploy at "verify image". A new `aws` call in the workflow needs a matching
  permission in `modules/github-oidc`.
- **ClickHouse needs no migration run on a fresh account.** analytics-service
  creates its database and its `events` table at startup
  (`ANALYTICS_ENSURE_SCHEMA`, on by default). The tables in
  `migrations/clickhouse/0001_analytics.sql` aren't used by any service. With
  `idle_scaling` on, its first start can time out while ClickHouse wakes up
  (`Database binbon_analytics does not exist`). ECS restarts the task, and
  the second start goes through.
- **Dev-only switches.** Dev's `env.hcl` turns on two things the other
  environments must decide on separately. The first is `OTP_FIXED_CODE` on
  auth (step 20). The second is `MEDIA_PRIVATE_ACCESS_ENABLED` on media: with
  it off, documents, view-once and `access=private` uploads answer 503
  `media_private_access`. Private access also needs `MEDIA_URL_SIGNING_KEY`
  and `INTERNAL_API_KEY`, and in production a non-empty `MEDIA_HLS_BASE_URL`.

- **SASL mechanism.** The backend supports `SCRAM-SHA-256` (default),
  `SCRAM-SHA-512` and `PLAIN`, selected by `KAFKA_SASL_MECHANISM`. Nothing in the
  infra sets it, so the SCRAM-SHA-256 default applies. Consider setting it
  explicitly so the mechanism is visible in the task definition rather than
  implied by a Rust fallback.
- **Redis is cluster-mode.** ElastiCache Serverless always is. Any multi-key
  Redis command (`ZUNIONSTORE`, `MGET`, `RENAME`, …) fails with `CROSSSLOT`
  unless all its keys share a hash tag.
- **No ERROR alerting exists.** A `tracing::error!` firing every 30 seconds went
  unnoticed for the life of a service, and recommendation-service logged ~6,700
  `TopicAuthorizationFailed` an hour while reporting healthy. Both were found by
  grepping, not by an alarm. A CloudWatch metric filter over the
  `/ecs/binbon-<env>/*` log groups is still the highest-value monitoring gap —
  step 17's guards stop new Kafka drift, but nothing yet catches the next
  unrelated silent failure.
