# Executor boundary

Plywo's Rails control plane owns GitHub authentication, durable execution state, stale guards, policy, and publication. The executor owns only the act of producing behavioral evidence for one exact execution request.

```text
GitHub webhook
  -> Rails control plane
  -> durable PlywoExecution
  -> executor request
  -> executor adapter
  -> executor result
  -> Rails stale guard
  -> GitHub Check + PR comment
```

## Portable request

The control plane converts `PlywoExecution` into `Plywo::Executor::Request` before dispatch. Schema version `1` contains:

```text
schema_version
execution_id
scenario_id
baseline_sha
candidate_sha
attempt_number
context.repository
context.pull_request_number
context.baseline_ref
context.candidate_ref
context.candidate_repository
```

The executor request deliberately excludes control-plane credentials and delivery internals. In particular it must not contain a GitHub App private key, installation token, webhook secret, installation ID, or webhook delivery ID.

A future remote executor may receive a separate short-lived capability for cloning a private repository, but that capability is not part of the stable execution request contract.

## Portable result

`Plywo::Executor::Result` schema version `1` turns the executor boundary into a two-way serialized contract.

A successful result contains the behavioral payload. A failed result contains only the source error class and message. Exception objects never cross the boundary.

```text
schema_version
status = succeeded | failed
payload
error_class
error_message
```

## Dispatch lifecycle

The GitHub orchestration job claims the durable execution and performs the first exact base/head check before enqueueing `PlywoExecutorJob` with a plain request hash.

`PlywoExecutorJob` reconstructs the request, runs the selected adapter, converts either the payload or exception into `Plywo::Executor::Result`, and enqueues `GithubPullRequestExecutionFinalizeJob`.

The finalizer is back inside the control-plane trust boundary. It renews the still-live execution lease, refreshes GitHub state, rejects stale results, classifies the durable execution, and publishes the Check Run and PR comment.

```text
GithubPullRequestExecutionJob
  -> claim attempt + lease
  -> GitHub preflight
  -> Request.to_h
  -> PlywoExecutorJob
       -> adapter
       -> Result.to_h
  -> GithubPullRequestExecutionFinalizeJob
       -> renew live lease
       -> GitHub stale guard
       -> durable outcome
       -> GitHub publication
```

The executor job does not receive a GitHub App token or private key.

## Execution leases

A successful claim creates a lease and records `heartbeat_at` plus `lease_expires_at`. The default lease is 30 minutes and can be configured with `PLYWO_EXECUTION_LEASE_SECONDS`.

A result is accepted only while the lease is still live. The finalizer renews that lease before doing network publication work. A late result cannot revive an execution whose lease has already expired.

Production Solid Queue runs `GithubPullRequestExecutionLeaseReaperJob` every minute. It schedules an expiry job for overdue GitHub executions. The expiry transition is atomic: it succeeds only while the execution is still `running` and its recorded lease is still expired. A concurrent finalizer that renewed the lease therefore wins safely and prevents expiry.

An abandoned execution becomes:

```text
status  = failed
outcome = infra_failure
failure = Plywo::Executor::LeaseExpired: ...
```

The control plane then publishes the normal `INFRA_FAILURE` Check and comment. Publication is idempotent, and the expiry job can retry publication for an execution already terminal with the same lease-expiry failure.

## Adapters

`PLYWO_EXECUTOR=local` selects the current development adapter. It uses the exact-worktree + isolated PostgreSQL + Solid Queue implementation behind `Plywo::Github::LocalPullRequestRunner`.

`PLYWO_GITHUB_EXECUTION_MODE=local` remains a temporary compatibility fallback for existing Development App setups.

Production must not assume a local clone on the Rails web/control-plane host. A future remote adapter should consume the same versioned request contract and return the same versioned result contract without changing GitHub orchestration or policy code.

## Trust boundary

The executor can report observations and execution failures. It does not decide whether a pull request may merge. The control plane remains authoritative for:

- exact recorded base/head identity
- stale checks before dispatch and finalization
- execution lease ownership and expiry
- behavioral outcome classification
- `INFRA_FAILURE` versus product regression
- retry eligibility and attempt counting
- GitHub publication

This keeps an executor replaceable: local process, container, VM, Kubernetes job, or another disposable worker can implement the same boundary.

## Remote heartbeat boundary

The current local adapter normally completes well inside the default lease. A future long-running remote executor should renew its lease through a narrow authenticated control-plane heartbeat endpoint rather than receiving database access or GitHub credentials. That heartbeat protocol is intentionally deferred to the remote-executor slice.
