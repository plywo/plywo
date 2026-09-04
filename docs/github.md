# GitHub integration

One Plywo run projects into several GitHub surfaces.

## PR comment

Concise human summary. Use GitHub-flavored Markdown and update one durable bot-owned comment instead of posting a new comment on every push.

## Check Run

Stable merge and agent state. The initial check name is:

```text
Plywo / Behavioral Diff
```

Decision mapping:

```text
allow  -> success
review -> neutral
block  -> failure
```

The check uses the Plywo `run_id` as `external_id`. GitHub Actions may assign its own Check Run page as `details_url`, so the output summary also carries an explicit link to the Actions execution. GitHub presents the latest `Plywo / Behavioral Diff` context for the current head; internal Check Run IDs may differ across workflow attempts.

## Annotations

Annotations are deliberately conservative. A finding is source-localized only when runtime evidence provides a trustworthy source and the attributed path is present in the exact `base...head` changed-file set.

Plywo currently recognizes two trusted source modes:

```text
explicit -> an integration supplied an exact source location
runtime  -> Plywo captured an application callsite while the signal occurred
```

Trust order is conservative:

```text
changed explicit source
        ↓
changed single runtime source
        ↓
otherwise no source annotation
```

An explicit source always wins. Automatic runtime attribution is accepted only when exactly one changed-code runtime location exists for the finding. If multiple runtime callsites are plausible, the regression still affects the Check conclusion and PR comment, but Plywo does not guess which line to blame.

```text
runtime evidence
      +
changed-file proof
      +
unambiguous source
      ↓
finding.source
      ↓
GitHub annotation
```

### Rails runtime sources

`Plywo::Rails::SourceLocator` is the shared project-callsite primitive for synchronous Rails signals. It excludes Plywo internals and dependency/runtime paths such as `vendor/`, `tmp/`, `.bundle/`, `log/`, and `storage/`, then returns the first application-owned frame.

Current automatic integrations:

```text
sql.active_record       -> SQL execution site
enqueue.active_job      -> background-job enqueue site
enqueue_at.active_job   -> scheduled-job enqueue site
deliver.action_mailer   -> synchronous email delivery site
```

The captured runtime source means "where this observed behavior happened". It is not necessarily the root cause of why a PR changed the behavior. For example, a changed configuration or loop count can create an extra job or email while the runtime source correctly points to the execution or delivery site. Future causal analysis may connect runtime sites to changed-code cause candidates, but GitHub annotations must not claim that inference today.

Background-job count changes currently produce a medium-severity `SIDE_EFFECT_CHANGED` finding, so their default merge recommendation is `REVIEW` rather than `BLOCK`. Email count changes currently produce a high-severity `SIDE_EFFECT_CHANGED` finding and therefore default to `BLOCK`. Both can carry a trusted runtime annotation when the application callsite is unambiguous and part of the changed-file set.

Action Mailer attribution currently covers synchronous `deliver_now` behavior. `deliver_later` first crosses an Active Job boundary, so Plywo must propagate execution context into the job before treating the eventual delivery as evidence from the originating execution.

This instrumentation is intended for Plywo executions such as CI and test environments, not as an always-on production profiler by default.

`Plywo::Rails::Evidence.attribute_next_line` remains a low-level explicit override. Keep the call on one physical line and place it immediately above the causal line that should receive the annotation. For integrations that already know the exact location, prefer `Plywo::Rails::Evidence.attribute(..., line:)`.

## Agent contract

Agents should never be required to parse the PR comment, Check Run, or annotations. Publish a versioned result JSON and later expose the same model through API/MCP.

```text
PR comment -> What changed?
Check      -> Can this merge?
Annotation -> Where is a confidently attributed runtime source?
Plywo UI   -> Why did it happen?
API/MCP    -> What should an agent do next?
```
