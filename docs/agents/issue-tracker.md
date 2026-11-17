# Issue tracker: GitHub

Issues and specs live in GitHub Issues in `Julesseg/health-analysis`. Use the `gh` CLI from this checkout, or select the repository explicitly with `--repo Julesseg/health-analysis`.

## Conventions

- Create an issue with `gh issue create --title "..." --body-file <file>`.
- Read an issue with `gh issue view <number> --json number,title,body,labels,comments`.
- List issues with `gh issue list --state open --json number,title,body,labels,comments`, adding label and state filters as needed.
- Comment with `gh issue comment <number> --body-file <file>`.
- Apply or remove labels with `gh issue edit <number> --add-label "..."` or `--remove-label "..."`.
- Close an issue with `gh issue close <number>` after recording its resolution.
- Put multiline bodies in a temporary UTF-8 file and pass `--body-file`, preserving actual newlines and literal text.
- Use the configured triage vocabulary when a skill names a triage role.

## Pull requests as a triage surface

**PRs as a request surface: no.**

GitHub shares numbering across issues and pull requests. When an ambiguous reference could name either, resolve it with `gh pr view <number>` and fall back to `gh issue view <number>`.

## Skill operations

When a skill says to publish to the issue tracker, create a GitHub issue. When it says to fetch a ticket, read the relevant issue including its comments and labels.

For a to-spec publication, use the complete specification as the issue body and apply `ready-for-agent` without an additional triage pass.

## Related issues and dependencies

Use native GitHub sub-issues and issue dependencies when supported. Dependency API operations require numeric issue database IDs, not issue numbers or node IDs. If these features are unavailable, use `Part of #<parent>` and `Blocked by: #<number>` references, with a task list on the parent. An issue is unblocked only when all its blockers are closed.
