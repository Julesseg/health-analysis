# Agent instructions

## Agent skills

### Issue tracker

Use GitHub Issues in `Julesseg/health-analysis`. Read `docs/agents/issue-tracker.md` before issue-tracker operations.

### Triage labels

Use the five default triage labels. Read `docs/agents/triage-labels.md` before triage or applying a triage label.

### Domain docs

Use the single-context layout: root `GLOSSARY.md` and `docs/adr/`. Read `docs/agents/domain.md` before codebase exploration or writing domain-facing output.

### Auto-dispatch

Read [auto-dispatch setup](docs/agents/auto-dispatch.md) before changing the
optional Paseo issue dispatcher or runner configuration.

## Application and tests

Keep application operations and observable state in the portable
`HealthAnalysisCore` Swift package. Extend `HealthAnalysisApplication` for
acceptance tests and the thin SwiftUI app. Use platform adapters for HealthKit
and temporary reopenable stores for persistence scenarios. See
[testing decisions](docs/spec.md#testing-decisions) for the agreed boundary.

Run `swift test --package-path Core` for application behavior. Use the native
`HealthAnalysisUITests` target for UI journeys. When local runtime verification
is unavailable, implement and build the UI where possible and record the
remaining XCUITest check. The macOS CI job runs the native suite.

Use the `simulator-lease` skill before opening, booting, testing, or capturing
a simulator. Release the reservation after runtime verification, shut down
the simulators you booted, and leave existing simulators running. Generic
builds require no reservation.

Use the parent's agent provider for any subagent, and verify the configured
provider and profile before spawning it. If unavailable, continue in the
current agent. A different provider requires an explicit user request.

## Commits and pull requests

Use Conventional Commits for commit subjects and PR titles. Commit on a
working branch and target `master` when the task calls for a pull request.
