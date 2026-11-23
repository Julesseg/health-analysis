# Auto-dispatch: ready issues to Paseo agent sessions

When configured, the dispatcher starts a Paseo session on a self-hosted Mac
runner for eligible `ready-for-agent` issues after their blockers close.
Both workflows skip their jobs until the three required Actions variables
are set.

## How it works

1. `unblock-dispatch.yml` scans open `ready-for-agent` issues when an issue is
   completed or the workflow is run manually. It reads GitHub issue
   dependencies and sub-issues, then dispatches up to three in-flight issues.
2. `agent-implement.yml` re-checks issue scope and state, validates the
   configured Paseo provider and model, fetches the checkout, and starts a
   background worktree session on `agent/issue-<N>`.

The instruction tells the selected agent to use the
`label-and-implement-with-pr` skill. Install that skill and its `implement`,
`ui-report`, and `babysit-pr` dependencies under `~/.agents/skills` on the
runner. Client-specific skill directories are compatibility adapters, not the
source of truth.

## Scope rules

- Automatic dispatch requires `ready-for-agent` at selection and again when the queued runner starts.
- Use native GitHub blocking relationships. An issue passes the dependency
  check when every blocker is closed.
- An issue with any native sub-issue is a parent and is skipped.
- A queued or active spawn run holds the issue until the session can apply
  `agent-dispatched`. The session applies the label after it starts.

## Paseo configuration

Set these repository Actions variables:

| Variable | Required | Default | Purpose |
| --- | --- | --- | --- |
| `PASEO_PROJECT_DIR` | yes | none | Checkout path on the runner |
| `PASEO_PROVIDER` | yes | none | Provider passed to `paseo run` |
| `PASEO_MODEL` | yes | none | Model passed to `paseo run` |
| `PASEO_THINKING` | no | unset | Optional reasoning option |
| `PASEO_MODE` | no | unset | Optional provider permission mode |
| `PASEO_BASE` | no | `origin/master` | Ref used to create the worktree branch |

There are no provider, model, thinking, or permission-mode defaults. The
workflow validates the provider status, authentication, model, and optional
thinking value before it fetches or creates a branch. Inspect valid values with:

```sh
paseo provider ls
paseo provider models <provider> --thinking
paseo provider diagnostic <provider>
```

The resulting command has this shape:

```sh
paseo run --background \
  --provider <provider> \
  --model <model> \
  --cwd <checkout> \
  --new-workspace worktree \
  --worktree-mode branch-off \
  --new-branch agent/issue-<N> \
  --base origin/master \
  "Use the label-and-implement-with-pr skill to implement issue #<N>."
```

Optional `--thinking` and `--mode` arguments are added only when configured.

## One-time Mac setup

1. Register a macOS self-hosted runner and install it as a service.
2. Start Paseo at login and confirm `paseo ls` works for the runner account.
3. Set `PASEO_PROJECT_DIR`, `PASEO_PROVIDER`, and `PASEO_MODEL`. Ensure the
   checkout's `origin` is reachable unattended.
4. Authenticate `gh` and the selected Paseo provider for the same account.

Run `unblock-dispatch.yml` manually to rescan eligible issues. Run
`agent-implement.yml` with an issue number to select a leaf issue directly.
The native dependency and sub-issue checks still apply. The `force` input
overrides the closed or already-claimed checks.
