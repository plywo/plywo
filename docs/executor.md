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

A remote executor may receive a separate short-lived capability for cloning a private repository, but that capability is not part of the stable execution request contract.

## Portable result

`Plywo::Executor::Result` schema version `1` is the return contract for every executor adapter.

A successful result contains the behavioral payload. A failed result contains only the source error class and message. Exception objects never cross the boundary.

```text
schema_version
status = succeeded | failed
payload
error_class
error_message
```

Adapters consume `Plywo::Executor::Request` and return `Plywo::Executor::Result`. `PlywoExecutorJob` fails closed if an adapter returns an unversioned application payload instead of the portable result contract.

## Dispatch lifecycle

The GitHub orchestration job claims the durable execution and performs the first exact base/head check before enqueueing `PlywoExecutorJob` with a plain request hash.

`PlywoExecutorJob` reconstructs the request, invokes the selected adapter, and enqueues `GithubPullRequestExecutionFinalizeJob` with `Result.to_h`. If the adapter itself raises before returning a result, the job converts that transport/adapter exception into a failed portable result.

The finalizer is back inside the control-plane trust boundary. It renews the still-live execution lease, refreshes GitHub state, rejects stale results, classifies the durable execution, and publishes the Check Run and PR comment.

```text
GithubPullRequestExecutionJob
  -> claim attempt + lease
  -> GitHub preflight
  -> Request.to_h
  -> PlywoExecutorJob
       -> adapter(Request)
       -> Result.to_h
  -> GithubPullRequestExecutionFinalizeJob
       -> renew live lease
       -> GitHub stale guard
       -> durable outcome
       -> GitHub publication
```

The executor job does not receive a GitHub App private key. Remote execution can receive a separate short-lived repository capability described below.

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

### Local

`PLYWO_EXECUTOR=local` selects the development adapter. It uses the exact-worktree + isolated PostgreSQL + Solid Queue implementation behind `Plywo::Github::LocalPullRequestRunner` and wraps either its payload or exception in `Plywo::Executor::Result`.

`PLYWO_GITHUB_EXECUTION_MODE=local` remains a temporary compatibility fallback for existing Development App setups.

### Remote HTTP

`PLYWO_EXECUTOR=remote` selects `Plywo::Executor::HttpAdapter`.

Required settings:

```text
PLYWO_REMOTE_EXECUTOR_URL=https://executor.example.com/v1/executions
PLYWO_REMOTE_EXECUTOR_TOKEN=...
```

Optional transport settings:

```text
PLYWO_REMOTE_EXECUTOR_OPEN_TIMEOUT_SECONDS=5
PLYWO_REMOTE_EXECUTOR_READ_TIMEOUT_SECONDS=2100
```

The adapter sends one `POST` containing `Request.to_h` JSON and expects one `Result.to_h` JSON response. Requests include:

```text
Content-Type: application/json
Accept: application/json
Authorization: Bearer <executor service token>
Idempotency-Key: <execution_id>:<attempt_number>
Plywo-Repository-Authorization: Bearer <short-lived repository capability>  # when available
```

The normal `Authorization` bearer authenticates the control plane to the executor service. It is not a GitHub token and is never added to the stable request body. The idempotency key gives a remote service a stable identity for duplicate transport submissions of the same attempt.

For a durable GitHub execution, the control plane can mint a second short-lived capability from the recorded installation. The token request is narrowed to the one repository and to `contents: read`. The resulting token is sent only in `Plywo-Repository-Authorization`; it is not added to `Request.to_h` or `Result.to_h`.

A non-2xx response, invalid JSON, or invalid result schema becomes a transport `INFRA_FAILURE`; a valid failed `Result` preserves the remote worker's original error class and message through finalization.

## Executor service role

The same codebase can now be deployed in a separate executor-service role. The endpoint is mounted only when:

```text
PLYWO_EXECUTOR_SERVICE=1
```

The service accepts:

```text
POST /v1/executions
```

and requires a dedicated bearer token:

```text
PLYWO_EXECUTOR_SERVICE_TOKEN=...
```

The control-plane `PLYWO_REMOTE_EXECUTOR_TOKEN` and the service-side `PLYWO_EXECUTOR_SERVICE_TOKEN` are the two ends of the same service-authentication credential. They are separate from GitHub App credentials.

Worker implementation is selected independently:

```text
PLYWO_EXECUTOR_SERVICE_ADAPTER=local
# or
PLYWO_EXECUTOR_SERVICE_ADAPTER=git_clone
```

`local` reuses an already-present checkout. `git_clone` requires the ephemeral repository capability and prepares a disposable Git workspace before invoking the same exact-worktree execution path.

This separation is intentional. A service deployment must not set `PLYWO_EXECUTOR=remote` and recursively call itself. It must not receive the GitHub App private key or webhook secret. The only GitHub credential it may receive is the per-execution, repository-scoped, contents-read clone capability.

### Durable transport idempotency

Every executor service request is stored in `plywo_executor_requests`, keyed uniquely by the HTTP `Idempotency-Key`. The ledger stores only the portable request, its digest, the portable result, and service-side claim metadata. It does not store either bearer token or the repository capability.

For the same idempotency key:

- the same completed request returns the previously stored `Result`
- a still-processing request returns conflict with `Retry-After`
- reuse with different request content is rejected
- an abandoned processing request can be reclaimed after its service-side claim lease expires
- a stale worker claim cannot overwrite the result after another worker has reclaimed the request

Request digests canonicalize nested hash key ordering before hashing, so semantically identical JSON objects do not conflict only because their keys were reordered.

The service-side request lease defaults to 40 minutes:

```text
PLYWO_EXECUTOR_SERVICE_REQUEST_LEASE_SECONDS=2400
```

This lease protects transport idempotency. It is separate from the control-plane `PlywoExecution` lease, which protects the product execution lifecycle.

### Repository clone capability

`Plywo::Github::RepositoryCapabilityProvider` loads the durable execution by `execution_id`, reads the installation ID only inside the control-plane trust boundary, and asks GitHub for a narrowed installation access token:

```text
repository: exact request repository
permissions:
  contents: read
```

The token is deliberately out-of-band from request serialization. The executor controller parses it into `Plywo::Executor::RepositoryCapability` and passes it to the selected worker adapter without adding it to `plywo_executor_requests`.

`GitCloneAdapter` currently supports same-repository pull requests. It initializes a disposable repository, configures the normal GitHub HTTPS remote, and fetches the recorded base branch plus the PR head ref. Authentication is supplied to Git through process environment Git config, not embedded in the clone URL or Git command arguments. The workspace is removed after the attempt.

The adapter still reuses `LocalPullRequestRunner`, so arbitrary customer repositories must expose the execution/instrumentation surface expected by the current capture runtime. Generalized instrumentation packaging is a separate boundary from repository authorization.

## Trust boundary

The executor can report observations and execution failures. It does not decide whether a pull request may merge. The control plane remains authoritative for:

- exact recorded base/head identity
- stale checks before dispatch and finalization
- execution lease ownership and expiry
- behavioral outcome classification
- `INFRA_FAILURE` versus product regression
- retry eligibility and attempt counting
- GitHub publication
- minting the short-lived repository capability

The executor service role owns only:

- authenticating the control-plane service credential
- consuming the short-lived clone capability for repository access
- durable idempotency for one execution attempt
- acquiring a service-side worker claim
- producing `Plywo::Executor::Result`

This keeps an executor replaceable: local process, container, VM, Kubernetes job, or another disposable worker can implement the same boundary.

## Remaining remote-runtime boundaries

Repository authorization now has an explicit out-of-band capability boundary, but production remote execution is not complete. The important remaining boundaries are:

1. heartbeat/cancellation for long-running remote work so useful work can renew the control-plane lease without database access
2. generalized subject instrumentation so an arbitrary customer repository does not need Plywo's dogfood files committed into it
3. fork pull requests, which require an explicit multi-repository capability model rather than reusing the base-repository capability
4. deployment isolation proving the executor role actually runs without the GitHub App private key or webhook secret
5. a real control-plane -> executor-service E2E on separate processes/hosts using the `git_clone` adapter

The live Development App infra-failure Re-run proof was completed in #35.
