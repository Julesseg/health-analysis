# Health Analysis

A personal native iPhone app for exploring associations between health measurements and behavior, using read-only Apple Health data and app-owned manual logs.

The app opens on Analysis with an empty saved list, a blank builder (+), Discover, and Settings. Log is the second tab and opens on today with a scrollable week strip. This scaffold establishes navigation; later slices add tracking fields, Health reads, analysis results and their Refresh button.

## Development

The scaffold comes from [iOS Swift App Template at 0229180](https://github.com/Julesseg/iOS-Swift-app-template/tree/02291809a7afc6c83a223e1773a5a41319c6b5d7). Open `App/HealthAnalysis.xcodeproj` and run the shared `HealthAnalysis` scheme. The iPhone app displays as **Health Analysis** and uses `com.julesseguin.healthanalysis`. It targets iOS 26.0 and later with Swift 6. CI builds with Xcode 27 and runs the portable Swift package using Swift 6.0.3 on Linux.

`HealthAnalysisCore` exposes `HealthAnalysisSession` to both SwiftUI and application acceptance tests. Run `swift test --package-path Core` and `node --test ci/dispatch-eligibility.test.cjs` locally. The native UI test exercises both tabs, the week strip, the builder, Discover and Settings on a single iPhone 15 Pro simulator. Use this model for local verification and visual reviews.

For a visual review, run the CI workflow manually with **Capture the five navigation screens for visual review** enabled, or set `TEST_RUNNER_CAPTURE_SCREENSHOTS=true` when invoking `xcodebuild test` on a leased simulator. CI uploads the test result bundle for failures and requested captures. Documentation-only changes skip the simulator job.

## Distribution

Installable PR builds require GitHub Pages, a registered device in the Ad Hoc provisioning profile, and four Actions secrets: `APPLE_TEAM_ID`, `APPLE_CERTIFICATE_P12`, `APPLE_CERTIFICATE_PASSWORD`, and `APPLE_PROVISIONING_PROFILE`. The certificate and profile are base64 encoded. The Pages environment must allow deployments from the PR. Set `NTFY_TOPIC` for optional notifications. See the [build pipeline](ci/README.md).

Tagged or manually dispatched App Store releases use the distribution certificate, its password, the team ID, and an App Store Connect key configured through `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, and `APP_STORE_CONNECT_KEY_P8`. The [agent dispatcher](docs/agents/auto-dispatch.md) requires a separately configured self-hosted runner and Paseo variables.

## Product documentation

- [Product design](docs/design.md)
- [Consolidated specification](docs/spec.md)
- [Native iOS interface design](docs/ui-design.md)
- [Domain glossary](GLOSSARY.md)
- [Native iPhone architecture decision](docs/adr/0001-native-iphone-on-device-analysis.md)
- [Data sources and verification still needed](docs/data-sources.md)
- [Analysis evidence and confidence](docs/analysis-evidence.md)
