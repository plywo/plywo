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

Annotations are deliberately conservative. A finding is source-localized only when both conditions are true:

1. runtime evidence supplied an explicit source attribution for that signal;
2. the attributed path is present in the exact `base...head` changed-file set.

Only then does the finding gain a versioned `source` object and project into a GitHub Check annotation. Unattributed runtime regressions still affect the Check conclusion and PR comment but never point at a guessed line of code.

```text
runtime attribution
      +
changed-file proof
      ↓
finding.source
      ↓
GitHub annotation
```

`Plywo::Rails::Evidence.attribute_next_line` is a low-level convenience marker. Keep the call on one physical line and place it immediately above the causal line that should receive the annotation. For integrations that already know the exact location, prefer `Plywo::Rails::Evidence.attribute(..., line:)`.

## Agent contract

Agents should never be required to parse the PR comment, Check Run, or annotations. Publish a versioned result JSON and later expose the same model through API/MCP.

```text
PR comment -> What changed?
Check      -> Can this merge?
Annotation -> Where is a confidently attributed source?
Plywo UI   -> Why did it happen?
API/MCP    -> What should an agent do next?
```
