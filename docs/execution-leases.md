# Execution leases

Plywo uses a durable lease on each claimed GitHub pull request execution so a worker that disappears cannot leave the control plane in `running` forever.

## Lifecycle

```text
queued
  -> claim!
  -> running + heartbeat_at + lease_expires_at
  -> executor result
     -> finalizer renews the live lease
     -> completed / failed / ignored

running + expired lease
  -> production reaper
  -> lease expiry job
  -> infra_failure
  -> GitHub action_required Check
  -> eligible for explicit re-run
```

`attempt_count` changes only when `claim!` succeeds. Lease expiry does not create a new attempt. A later GitHub re-run first requeues the same durable execution and the next successful claim increments the attempt.

## Safety properties

- only `running` executions with an overdue lease can be expired
- renewal and expiry are conditional database updates, so a renewed lease wins over an already-enqueued stale expiry job
- late executor results cannot finalize an expired or terminal execution
- an expired execution is classified as `infra_failure`, never as a behavioral regression
- publication is retriable after the durable lease failure has already been recorded
- stale base/head state suppresses publication for an obsolete pull request execution

## Production schedule

`GithubPullRequestExecutionLeaseReaperJob` runs every minute in production and schedules `GithubPullRequestExecutionLeaseExpiryJob` for overdue GitHub executions.

The default lease is 30 minutes and can be changed with `PLYWO_EXECUTION_LEASE_SECONDS`.

The current lease is intentionally conservative and does not yet implement continuous heartbeats from a remote executor. A future remote transport must renew the lease while useful work is still progressing rather than simply increasing the timeout indefinitely.
