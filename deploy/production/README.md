# Plywo production deployment

This directory defines the first production-realistic deployment contract for Plywo.

## Topology

```text
GitHub
  -> https://app.plywo.com
       -> Cloudflare Tunnel
       -> control_plane container
            -> managed PostgreSQL
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

## Host 1: control plane

Copy:

```text
control-plane.env.example -> .env.control-plane
tunnel.env.example        -> .env.control-plane.tunnel
```

Create:

```text
.secrets/plywo-github-private-key.pem
```

The private key file must be readable only by the deployment operator and mounted read-only into the container at `/run/secrets/plywo-github-private-key.pem`.

Required external dependency:

- durable PostgreSQL endpoint for `DATABASE_URL`

Required Cloudflare Tunnel route:

```text
app.plywo.com -> http://plywo:3000
```

Start:

```bash
export PLYWO_IMAGE_TAG=sha-<full-git-sha>
docker compose -f compose.control-plane.yml pull
docker compose -f compose.control-plane.yml up -d
```

Verify:

```bash
curl -fsS https://app.plywo.com/up
curl -fsS https://app.plywo.com/ready
curl -fsS https://app.plywo.com/onboarding >/dev/null
```

`/ready` must report `{"status":"ready","role":"control_plane","errors":[]}` before GitHub webhook traffic is enabled.

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
export PLYWO_IMAGE_TAG=sha-<same-full-git-sha>
docker compose -f compose.executor.yml pull
docker compose -f compose.executor.yml up -d
```

Verify:

```bash
curl -fsS https://executor.plywo.com/up
curl -fsS https://executor.plywo.com/ready
```

`/ready` must report `{"status":"ready","role":"executor_service","errors":[]}`.

The executor route is service-authenticated. Do not configure GitHub App credentials on this host.

## Image release

`.github/workflows/release-image.yml` publishes the same Dockerfile to GHCR on either:

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
| GitHub App private key | yes | **never** |
| GitHub webhook secret | yes | **never** |
| GitHub App id/client id | yes | no |
| remote/executor service token | client side | server side |
| Cloudflare Tunnel token | control-plane tunnel only | executor tunnel only |
| executor PostgreSQL password | no | yes |
| control-plane `DATABASE_URL` | yes | no |

The two Cloudflare Tunnel tokens must also remain separate.

## Production GitHub App registration

Only after both `/ready` endpoints are green:

1. set the control plane `PLYWO_PUBLIC_URL=https://app.plywo.com`;
2. open `https://app.plywo.com/github/app/register` while the production manifest environment is selected;
3. register `Plywo` under the `plywo` organization;
4. save the returned production App credentials to the control-plane secret store;
5. restart the control plane and re-check `/ready`;
6. verify the public App install page returns to `https://app.plywo.com/onboarding` after installation.

The browser registration/ownership confirmation is the one intentionally manual step.

## Cross-account acceptance

The deployment is not considered product-proven until #75 is completed from a repository owned outside the `plywo` GitHub account/org and both outcomes are observed:

```text
deliberate SQL regression -> DATABASE_QUERY_REGRESSION -> BLOCK
neutral candidate          -> no behavioral regression -> ALLOW
```

Record webhook delivery IDs, execution IDs, Check Run IDs, PR comment IDs, exact base/head SHAs, and install-to-first-review elapsed time in #75.
