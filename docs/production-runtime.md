# Production runtime

Plywo production is intentionally split into two trust domains even though both roles currently ship from the same Rails codebase.

```text
GitHub
  -> control plane
       -> durable PlywoExecution
       -> HTTPS executor request + short-lived repository capability
            -> executor service
                 -> disposable Git clone/worktrees
                 -> behavioral evidence
       <- portable Result v1
  -> control-plane finalization
  -> GitHub Check + PR feedback
```

## Runtime roles

Set `PLYWO_RUNTIME_ROLE` explicitly in production.

### `control_plane`

Owns:

- GitHub App webhook ingress
- GitHub App private key and installation authentication
- durable product execution lifecycle
- execution leases, cancellation authority, stale guards and finalization
- minting short-lived repository clone capabilities
- behavioral policy and GitHub publication
- remote executor dispatch

The control plane must not execute customer repositories locally in production.

### `executor_service`

Owns:

- authenticated `/v1/executions` transport
- durable executor-request idempotency/cancellation ledger
- consumption of one short-lived repository-scoped clone capability
- disposable customer repository checkout
- subject environment discovery and execution
- portable `Result v1`

The executor service must not receive the GitHub App private key or webhook secret and must not be configured to recursively dispatch to another remote executor through the control-plane adapter.

### `combined`

`combined` mounts both route families and is the default convenience role in development/test.

Production `/ready` deliberately rejects `combined`. Deployment isolation is part of the product boundary, not only an operational preference.

## Liveness vs readiness

```text
GET /up
GET /ready
```

`/up` is Rails process liveness.

`/ready` is the Plywo deployment gate. It checks database connectivity plus role-specific production safety requirements. It returns `503` until the role is safe to receive traffic.

The readiness response contains only status, role and configuration error descriptions. It never returns secret values and database exceptions are reduced to their class rather than their message.

## Production environment matrix

| Setting | Control plane | Executor service |
| --- | --- | --- |
| `PLYWO_RUNTIME_ROLE` | `control_plane` | `executor_service` |
| `DATABASE_URL` | required | required |
| `PLYWO_PUBLIC_URL` | HTTPS required | do not need |
| `PLYWO_GITHUB_APP_ID` | required | do not need |
| `PLYWO_GITHUB_WEBHOOK_SECRET` | required | forbidden |
| `PLYWO_GITHUB_PRIVATE_KEY_PATH` | readable file required | forbidden |
| `PLYWO_EXECUTOR` | `remote` | must not be `remote` |
| `PLYWO_REMOTE_EXECUTOR_URL` | HTTPS required | forbidden |
| `PLYWO_REMOTE_EXECUTOR_TOKEN` | required | forbidden |
| `PLYWO_EXECUTOR_SERVICE_TOKEN` | do not need | required |
| `PLYWO_EXECUTOR_SERVICE_ADAPTER` | do not need | `git_clone` |

The control-plane `PLYWO_REMOTE_EXECUTOR_TOKEN` and executor-side `PLYWO_EXECUTOR_SERVICE_TOKEN` are the two ends of the same service-authentication credential. They should be injected into different deployments.

## Route surface

### Control plane

```text
POST /github/webhooks
GET  /github/app/register
GET  /github/app/manifest/callback
GET  /up
GET  /ready
```

### Executor service

```text
POST /v1/executions
POST /v1/executions/:execution_id/attempts/:attempt_number/cancel
GET  /up
GET  /ready
```

GitHub routes are not mounted on an `executor_service` deployment. Executor routes are not mounted on a `control_plane` deployment.

## GitHub App visibility

The production manifest `.github/app-manifest.json` is public because Plywo v0.1 must be installable on customer GitHub accounts. Development and staging manifests remain private so internal environments are not distributable apps.

Public visibility does not imply GitHub Marketplace publication. A public GitHub App can be installed directly from its installation page while Marketplace remains a later product/distribution decision.

## Compatibility

`PLYWO_EXECUTOR_SERVICE=1` remains a compatibility signal. When `PLYWO_RUNTIME_ROLE` is absent, that flag resolves the deployment to `executor_service`.

New deployments should set `PLYWO_RUNTIME_ROLE` explicitly.

## Deployment gate

Before routing production traffic:

```text
control plane /up    -> 200
control plane /ready -> 200
executor /up         -> 200
executor /ready      -> 200
```

A successful liveness check with failed readiness is not a healthy Plywo deployment.

## Still deliberately deferred

This slice establishes runtime isolation and configuration readiness. It does not yet provide:

- a container image / concrete hosting target
- hard worker/container termination
- worker-host heartbeat independent of control-plane queueing
- fork PR multi-repository capabilities
- arbitrary customer setup shell hooks
- non-Rails subject runtimes

The next deployment slice should package these two roles into an actual repeatable production artifact and prove a control-plane -> executor-service request across separate processes or hosts.
