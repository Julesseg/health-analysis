#!/usr/bin/env bash
set -euo pipefail

if [ "${AGENT_REMOTE:-false}" = "true" ]; then
  cat <<'EOF'
ENV=REMOTE LINUX. No iOS simulator/runtime exists here, so the App/ Xcode
target and the HealthAnalysisUITests XCUITest suite cannot run on this machine. Exercise
the portable logic with `cd Core && swift test`, implement UI work normally,
and let the `App · XCUITest (macOS)` CI job verify UI behavior.
EOF
elif [ "$(uname -s)" = "Linux" ]; then
  cat <<'EOF'
ENV=LOCAL LINUX. No Xcode or iOS simulator exists here, so the App/ target and
the HealthAnalysisUITests XCUITest suite cannot run on this machine. Implement UI work
normally and let CI verify it.
EOF
  if command -v swift >/dev/null 2>&1 || [ -x "$HOME/.local/share/swiftly/bin/swift" ]; then
    printf '%s\n' 'A Swift toolchain is available. Run the portable tests with `cd Core && swift test`.'
  else
    printf '%s\n' 'No Swift toolchain was found. Report that local Core tests could not run; CI still runs them.'
  fi
elif command -v xcodebuild >/dev/null 2>&1; then
  cat <<'EOF'
ENV=LOCAL MAC. Run portable checks with `cd Core && swift test`.
Use the simulator-lease skill before opening, booting, testing, or capturing
a simulator. Use the leased simulator's UDID for local XCUITest:
  cd App && xcodebuild test -project HealthAnalysis.xcodeproj -scheme HealthAnalysis \
    -destination 'platform=iOS Simulator,id=<leased-udid>' CODE_SIGNING_ALLOWED=NO
Finish the reservation as soon as runtime verification ends. The
App · XCUITest (macOS) CI job is the shared runtime gate.
EOF
fi
