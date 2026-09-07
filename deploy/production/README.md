# Plywo production deployment

This directory defines the first production-realistic deployment contract for Plywo.

## Topology

```text
GitHub
  -> https://app.plywo.com
       -> Cloudflare Tunnel
       -> control_plane container
            -> durable PostgreSQL
            -> https://executor.plywo.com
                 -> Cloudflare Tunnel
                 -> executor_service container
                      -> local PostgreSQL authority for executor ledger and disposable customer PostgreSQL subjects
                      -> disposable Git clone/worktrees
```

The two roles use the same immutable `ghcr.io/plywo/plywo` image but must run on separate hosts or otherwise separate trust domains.

The control plane owns GitHub credentials and must use `PLYWO_EXECUTOR=remote`.
The executor must never receive the GitHub App private key, webhook secret, or remote-executor credentials.

## Why two hosts, not Kubernetes

The product boundary already requires isolation, but the first production proof does not require a scheduler. Two small Linux hosts keep the trust boundary explicit, operational debugging simple, and the path to later Kubernetes migration straightforward because the runtime contract is already containerized and role-driven.

Do not deploy `PLYWO_RUNTIME_ROLE=combined` in production; `/ready` rejects it.

## Immutable image inputs

On each host copy:

```text
images.env.example -> .env
```

Fill immutable references:

```text
PLYWO_IMAGE_TAG=sha-<full-git-sha>
PLYWO_CLOUDFLARED_IMAGE=cloudflare/cloudflared@sha256:<digest>
PLYWO_POSTGRES_IMAGE=postgres@sha256:<digest> # executor host only
```

The application SHA must be identical on both roles. Pinning the supporting images makes rollback deterministic instead of silently following mutable Docker tags.

## Host 1: control plane

Copy:

```text
control-plane.env.example -> .env.control-plane
tunnel.env.example        -> .env.control-plane.tunnel
```

Create the secret directory before the first start:

```bash
mkdir -p .secrets
chmod 700 .secrets
```

After GitHub App registration, place the returned private key at:

```text
.secrets/plywo-github-private-key.pem
```

The directory is mounted read-only into the application container as `/run/secrets`. The private key itself therefore does not need to exist during the pre-registration bootstrap phase.

Required external dependency:

- durable PostgreSQL endpoint for `DATABASE_URL`

Required Cloudflare Tunnel route:

```text
app.plywo.com -> http://plywo:3000
```

Start:

```bash
docker compose -f compose.control-plane.yml pull
docker compose -f compose.control-plane.yml up -d
```

## Host 2: executor

Copy:

```text
executor.env.example          -> .env.executor
executor-postgres.env.example -> .env.executor.postgres
tunnel.env.example            -> .env.executor.tunnel
```

Use the same randomly generated service credential on opposite sides:

```text
control plane: PLYWO_REMOTE_EXECUTOR_TOKEN
executor:      PLYWO_EXECUTOR_SERVICE_TOKEN
```

The executor PostgreSQL password must match between `.env.executor.postgres`, `DATABASE_URL`, and `PLYWO_LOCAL_POSTGRES_URL`.

Required Cloudflare Tunnel route:

```text
executor.plywo.com -> http://plywo:3000
```

Start:

```bash
docker compose -f compose.executor.yml pull
docker compose -f compose.executor.yml up -d
```

The executor route is service-authenticated. Do not configure GitHub App credentials on this host.

## Production bootstrap is intentionally two-phase

The production control plane cannot be fully ready before the production GitHub App exists because `/ready` requires the App id, webhook secret, and readable private key. Registration therefore has a narrow bootstrap phase rather than weakening readiness.

### Phase A: register the App

On the control plane:

1. set `PLYWO_GITHUB_APP_MANIFEST_ENV=production`;
2. set `PLYWO_ENABLE_GITHUB_APP_REGISTRATION=1`;
3. set `PLYWO_PUBLIC_URL=https://app.plywo.com`;
4. provide a valid `SECRET_KEY_BASE`, `DATABASE_URL`, remote executor URL/token, and the other non-App production settings;
5. leave the not-yet-issued App id/webhook secret/private key absent;
6. start the deployment.

Expected state:

```text
GET /up                       -> 200
GET /github/app/register      -> 200
GET /ready                    -> 503 (expected until App credentials exist)
```

Open:

```text
https://app.plywo.com/github/app/register
```

Register `Plywo` under the `plywo` organization. The production callback displays the one-time credentials; save them immediately to the control-plane secret store and write the private key to `.secrets/plywo-github-private-key.pem`.

The browser registration/organization-owner confirmation is the one intentionally manual step.

### Phase B: become production-ready

Populate:

```text
PLYWO_GITHUB_APP_ID
PLYWO_GITHUB_CLIENT_ID
PLYWO_GITHUB_WEBHOOK_SECRET
PLYWO_GITHUB_PRIVATE_KEY_PATH=/run/secrets/plywo-github-private-key.pem
```

Then disable bootstrap registration again:

```text
PLYWO_ENABLE_GITHUB_APP_REGISTRATION=0
```

Restart the control plane and verify the complete topology:

```bash
bash ../../bin/verify-production-topology \
  https://app.plywo.com \
  https://executor.plywo.com
```

Expected readiness payloads:

```json
{"status":"ready","role":"control_plane","errors":[]}
{"status":"ready","role":"executor_service","errors":[]}
```

Only after this gate is green should production GitHub webhook traffic be treated as live.

## Image release

`.github/workflows/release-image.yml` publishes the repository Dockerfile to GHCR on either:

- a manual `workflow_dispatch`, or
- a `v*` Git tag.

Every release publishes an immutable `sha-<full-git-sha>` tag. Deploy both roles from the same SHA tag so the Request/Result contracts cannot drift between the control plane and executor.

If the GHCR package is private, each production host needs a read-only registry credential before `docker compose pull`. The GitHub Actions publisher itself uses the repository `GITHUB_TOKEN` and does not require a separate package-write secret.

## Cloudflare Tunnel

Use two remotely-managed tunnels, one per host. Keep their tokens in separate `.env.*.tunnel` files so the tunnel credential is not injected into the Plywo application container.

The first production proof intentionally uses Tunnel for stable HTTPS and avoids opening inbound application ports on either host.

## Secret split

| Secret / credential | Control plane | Executor |
| --- | --- | --- |
| `SECRET_KEY_BASE` | own value | different value |
| GitHub App private key | yes | **never** |
| GitHub webhook secret | yes | **never** |
| GitHub App id/client id | yes | no |
| remote/executor service token | client side | server side |
| Cloudflare Tunnel token | control-plane tunnel only | executor tunnel only |
| executor PostgreSQL password | no | yes |
| control-plane `DATABASE_URL` | yes | no |

The two Cloudflare Tunnel tokens and two Rails `SECRET_KEY_BASE` values must remain separate.

## Post-install verification

The production manifest points GitHub back to:

```text
https://app.plywo.com/onboarding
```

After registration, verify that the public App installation page can be opened by an account outside `plywo` and that post-install setup lands on the onboarding page.

## Cross-account acceptance

The deployment is not considered product-proven until #75 is completed from a repository owned outside the `plywo` GitHub account/org and both outcomes are observed:

```text
deliberate SQL regression -> DATABASE_QUERY_REGRESSION -> BLOCK
neutral candidate          -> no behavioral regression -> ALLOW
```

Record webhook delivery IDs, execution IDs, Check Run IDs, PR comment IDs, exact base/head SHAs, and install-to-first-review elapsed time in #75.
