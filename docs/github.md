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

For Rails SQL evidence, Plywo captures the synchronous application callsite from `sql.active_record` and excludes dependency/runtime paths such as `vendor/`, `tmp/`, and `.bundle/`. This instrumentation is intended for Plywo executions such as CI and test environments, not as an always-on production profiler by default.

`Plywo::Rails::Evidence.attribute_next_line` remains a low-level explicit override. Keep the call on one physical line and place it immediately above the causal line that should receive the annotation. For integrations that already know the exact location, prefer `Plywo::Rails::Evidence.attribute(..., line:)`.

## Agent contract

Agents should never be required to parse the PR comment, Check Run, or annotations. Publish a versioned result JSON and later expose the same model through API/MCP.

```text
PR comment -> What changed?
Check      -> Can this merge?
Annotation -> Where is a confidently attributed source?
Plywo UI   -> Why did it happen?
API/MCP    -> What should an agent do next?
```
