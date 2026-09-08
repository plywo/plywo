# Customer code execution boundary

Plywo intentionally executes customer repository code only inside the executor trust boundary. The control plane authenticates GitHub events, owns durable execution state and policy, mints short-lived repository capabilities, and publishes results; it does not run customer code.

## Explicit process services

`subject.services` may declare supporting processes needed by a behavioral capture. The supported providers remain intentionally narrow:

- service type is `process`
- runtime is explicitly `ruby` or `node`
- Ruby uses executor-owned `RbConfig.ruby`; Node uses the executor-owned fixed `node` executable
- customer configuration cannot select an arbitrary executable or shell command
- `SetupPlanCompiler` requires the requested runtime to be declared by executor runtime capabilities before the service can be planned
- the entrypoint is repository-relative and its real path must resolve to a file inside the disposable checkout
- arguments are passed as argv; no shell expansion is used
- the executor assigns the listening port and exports the resulting service URL
- readiness is bounded HTTP polling and capture starts only after readiness succeeds
- services are terminated before subject-state cleanup, including readiness and capture failures

The executor inherits only a small allowlist of host environment variables. A configured service URL cannot overwrite an existing capture environment value.

Adding another runtime must be implemented as another reviewed executor-owned provider. It must not turn `subject.services` into a generic command or shell DSL.

## Runtime capability boundary

A repository declaration does not prove that a runtime exists or authorize an executor to use it. `RuntimeCapabilities` is the executor-side authority. `SetupPlanCompiler` fails closed when a service requests a runtime that the current executor has not declared.

The production image declares its Node version in `PLYWO_EXECUTOR_CAPABILITIES_JSON`. The Docker build proof compares that declaration with `node --version`, then runs a real Node HTTP service through `plywo.yml -> Configuration -> SetupPlanCompiler -> ServiceExecutor -> Lifecycle`, including dynamic port assignment, readiness, capture, process teardown, and state cleanup.

## Credential and persistence boundary

Executor deployments must not receive the GitHub App private key or webhook secret. Private-repository access uses a separate short-lived, repository-scoped, contents-read capability. That capability is consumed by the disposable repository adapter and is not serialized into the stable Request/Result contracts or persisted in the executor request ledger.

Production Lab and the remote-executor topology proof exercise these boundaries, including service readiness/teardown, control-plane/executor secret separation, Request v1 dispatch, and repository-capability non-persistence.

## Static-analysis exception policy

Brakeman reports each intentional `Process.spawn` provider boundary as an `Execute` command-injection warning even though the executable is executor-owned and no shell is involved. Plywo does not disable the `Execute` check. `config/brakeman.ignore` suppresses only the individually reviewed Ruby and Node warning fingerprints for `Plywo::Subject::ServiceExecutor#start_process`, with a threat-model note for each provider.

`config/brakeman.yml` requires every ignored warning to have a note and fails CI when an ignore entry becomes obsolete. A code change that alters either execution boundary therefore produces a new fingerprint or an obsolete suppression and requires explicit review instead of silently inheriting the exception.
