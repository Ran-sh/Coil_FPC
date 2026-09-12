# Agent workflow

Use `AGENTS.md` for stable repository facts. Load a skill only when its task boundary
matches the work. Keep commit IDs, logs, temporary paths, plans, and review transcripts in
the task handoff so permanent instructions stay short and current.

For a substantial task, make the goal, relevant context, constraints, and done condition
explicit. Resolve routine choices from the repository and user request; ask only when a
missing decision changes scope, correctness, or authority. Continue authorized work through
verification and report meaningful state changes.
The invoking harness selects the model and reasoning effort; do not encode a competing
model choice in repository instructions.

## Proportionate validation

| Change | Evidence |
| --- | --- |
| Documentation or agent guidance | Check links, commands, metadata, contradictions, and diff hygiene. |
| Workflow YAML | Parse YAML; verify permissions, triggers, job graph, Action pins, decoded commands, and upload paths. |
| Local MATLAB behavior | Run focused tests for the affected feature. |
| Public API, geometry, manufacturing, or export contract | Run the affected module's full verification suite. |
| Release candidate | Use both repository skills and bind tests/artifacts/visuals to the exact candidate. |

Run each module separately from its root:

```text
matlab -batch "addpath('tests'); results = run_all_verification();"
```

The runners reject empty or failed suites. Derive counts from the current run. Do not
repeat a full suite for a prose-only edit unless a changed command or unresolved concern
requires it.

## CI contract

- Circular and rectangular test jobs run independently.
- Each artifact job depends only on its matching successful test job.
- Generation validates status, reports, DXF, SVG, and manifest before upload.
- Rectangular staging reads through `RectangularFpc.Publish.Read_Committed`.
- Each upload uses one exact directory named with the full commit SHA.
- Third-party Actions stay pinned to reviewed commit SHAs, and MATLAB stays aligned with
  the documented release.

Preserve these contracts when improving readability or speed. Wait on the existing CI run;
inspect failures before retrying and report meaningful state changes rather than unchanged
polls.

## Review handoff

Use the requested reviewer through its available contract and preserve the session identity.
Verify the selected model and effort from runtime evidence when the review depends on them.
For GitHub reviews, request exact commit/file reads and label artifact hashes, rendered images,
and tool limitations. Missing evidence is an evidence gap, not a discovered code defect.

Present substantive findings before implementing an authorized correction batch. A review
approval applies to the examined snapshot; merge, tag, push, and publication are separate
actions authorized by the user.
