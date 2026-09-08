# Subject execution identity

Production executors separate executor-owned control operations from customer-controlled repository execution with a dedicated operating-system identity.

The production image declares:

- `PLYWO_SUBJECT_UID`
- `PLYWO_SUBJECT_GID`
- `PLYWO_SUBJECT_HOME`
- `PLYWO_SUBJECT_USER`

The four values are an all-or-nothing contract. The UID and GID must be positive, the subject UID must differ from the executor UID, and the home path must be absolute. Local development remains unchanged when none of the variables are present.

Customer-controlled Bundler/package-manager execution, Rails preparation, explicit process services, behavioral capture, and capture descendants use this identity. Executor-owned Git/worktree operations and installation of the exact Bundler tool version remain outside it.

Baseline and candidate use the same subject identity but never have writable workspaces at the same time. Each side is activated immediately before its lifecycle and sealed back to the executor in an `ensure` path before the next side becomes writable.

This boundary is a prerequisite for production container-service authority. It does not itself enable Compose or expose a Docker socket/runtime credential to the executor container.
