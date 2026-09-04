# Executor boundary

Plywo's Rails control plane owns GitHub authentication, durable execution state, stale guards, policy, and publication. The executor owns only the act of producing behavioral evidence for one exact execution request.

```text
GitHub webhook
  -> Rails control plane
  -> durable PlywoExecution
  -> executor request
  -> executor adapter
  -> behavioral result
  -> Rails stale guard
  -> GitHub Check + PR comment
```

## Portable request

The control plane converts `PlywoExecution` into `Plywo::Executor::Request` before invoking an executor. Schema version `1` contains:

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

## Adapters

`PLYWO_EXECUTOR=local` selects the current development adapter. It uses the exact-worktree + isolated PostgreSQL + Solid Queue implementation behind `Plywo::Github::LocalPullRequestRunner`.

`PLYWO_GITHUB_EXECUTION_MODE=local` remains a temporary compatibility fallback for existing Development App setups.

Production must not assume a local clone on the Rails web/control-plane host. A future remote adapter should consume the same versioned request contract and return the same behavioral result payload without changing GitHub orchestration or policy code.

## Trust boundary

The executor can report observations and execution failures. It does not decide whether a pull request may merge. The control plane remains authoritative for:

- exact recorded base/head identity
- stale checks before and after execution
- behavioral outcome classification
- `INFRA_FAILURE` versus product regression
- retry eligibility and attempt counting
- GitHub publication

This keeps an executor replaceable: local process, container, VM, Kubernetes job, or another disposable worker can implement the same boundary.
