# GitHub integration

One Plywo run projects into several GitHub surfaces.

## PR comment

Concise human summary. Use GitHub-flavored Markdown and update one durable comment instead of posting a new comment on every push.

## Check Run

Stable merge/agent state. Initial stable name:

```text
Plywo / Behavioral Diff
```

Expose the Plywo run as `external_id` and link `details_url` to the full investigation.

## Annotations

Use source-localized annotations only when a finding can be mapped confidently to changed code.

## Agent contract

Agents should never be required to parse the PR comment. Publish a versioned result JSON and later expose the same model through API/MCP.

```text
PR comment -> What changed?
Check      -> Can this merge?
Annotation -> Where is the likely source?
Plywo UI   -> Why did it happen?
API/MCP    -> What should an agent do next?
```
