# Customer code execution boundary

Plywo intentionally executes customer repository code only inside the executor trust boundary. The control plane authenticates GitHub events, owns durable execution state and policy, mints short-lived repository capabilities, and publishes results; it does not run customer code.

## Explicit process services

`subject.services` may declare supporting processes needed by a behavioral capture. The first supported provider is intentionally narrow:

- service type is `process`
- runtime is explicitly `ruby`
- the executable is executor-owned `RbConfig.ruby`
- customer configuration cannot select an arbitrary executable or shell command
- the entrypoint is repository-relative and its real path must resolve to a file inside the disposable checkout
- arguments are passed as argv; no shell expansion is used
- the executor assigns the listening port and exports the resulting service URL
- readiness is bounded HTTP polling and capture starts only after readiness succeeds
- services are terminated before subject-state cleanup, including readiness and capture failures

The executor inherits only a small allowlist of host environment variables. A configured service URL cannot overwrite an existing capture environment value.

## Credential and persistence boundary

Executor deployments must not receive the GitHub App private key or webhook secret. Private-repository access uses a separate short-lived, repository-scoped, contents-read capability. That capability is consumed by the disposable repository adapter and is not serialized into the stable Request/Result contracts or persisted in the executor request ledger.

Production Lab and the remote-executor topology proof exercise these boundaries, including service readiness/teardown, control-plane/executor secret separation, Request v1 dispatch, and repository-capability non-persistence.

## Static-analysis exception policy

Brakeman reports the intentional `Process.spawn` boundary as an `Execute` command-injection warning even though the executable is fixed and no shell is involved. Plywo does not disable the `Execute` check. `config/brakeman.ignore` suppresses only the reviewed warning fingerprint for `Plywo::Subject::ServiceExecutor#start_process` and records the threat-model rationale.

`config/brakeman.yml` requires every ignored warning to have a note and fails CI when an ignore entry becomes obsolete. A code change that alters this execution boundary therefore produces a new fingerprint or an obsolete suppression and requires explicit review instead of silently inheriting the exception.
