# Agent instructions

## Agent skills

### Issue tracker

Use GitHub Issues in `Julesseg/health-analysis`. Read `docs/agents/issue-tracker.md` before issue-tracker operations.

### Triage labels

Use the five default triage labels. Read `docs/agents/triage-labels.md` before triage or applying a triage label.

### Domain docs

Use the single-context layout: root `GLOSSARY.md` and `docs/adr/`. Read `docs/agents/domain.md` before codebase exploration or writing domain-facing output.

### Application development

Keep portable application behavior in `HealthAnalysisCore`. Drive acceptance tests through the same `HealthAnalysisSession` used by SwiftUI. Keep platform data access at the edge. Run `swift test --package-path Core` for portable changes. Implement native UI for issues that request it and verify navigation through the macOS CI XCUITest job.

Use the `simulator-lease` skill before any simulator runtime work. Finish the lease immediately after verification and preserve previously booted devices. Use the parent's provider for subagents and verify provider and profile before spawning. Continue in the current agent if that provider is unavailable.

Use Conventional Commits for commit subjects and PR titles. Target the repository's default branch. Read `docs/agents/auto-dispatch.md` before changing the optional dispatcher.
