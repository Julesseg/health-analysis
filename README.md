# Health Analysis

A personal native iPhone app for exploring associations between health
measurements and behavior. The product design uses read-only Apple Health data
and app-owned manual logs.

The initial app opens to Insights and provides Explore and Data tabs plus
separate Log and Settings actions. The screens show the empty state before
data collection and analysis are implemented.

## Build and test

- The Xcode project and shared scheme are named `HealthAnalysis`. The app
  displays as Health Analysis and uses bundle ID `com.julesseg.healthanalysis`.
  The UI test target is `HealthAnalysisUITests`.
- The app targets iPhone on iOS 26 or later for native Liquid Glass. Build
  with Xcode 26 or later in Swift 6 language mode. The Core package uses
  Swift tools 6.0 and CI runs it with Swift 6.0.3 on Linux.
- CI runs on pull requests and pushes to `master`. It checks Core, the issue
  dispatcher, and native launch and navigation on an iPhone simulator using
  the stable Xcode available on the macOS runner.

```sh
swift test --package-path Core
node --test ci/dispatch-ready-issues.test.cjs
xcodebuild -project App/HealthAnalysis.xcodeproj -scheme HealthAnalysis \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## Application interface

The SwiftUI app constructs `HealthAnalysisApplication` from
`HealthAnalysisCore` and reads its `overview` for the initial display.
Use that application interface for downstream operations and observable
states, including daily logging and HealthKit-backed data. Keep HealthKit at
the platform edge and test workflow behavior through the same public
interface with a deterministic Health data adapter or a temporary reopenable
store as appropriate. Native launch and navigation have a separate XCUITest.

The interface decisions and verification scope are in the
[specification](docs/spec.md#testing-decisions). Add user-facing strings
through the app's `Localizable.xcstrings` catalog.

## Enabling installable PR builds

The optional PR release workflow needs an Apple Developer membership,
an Apple Distribution certificate, an Ad Hoc provisioning profile for
`com.julesseg.healthanalysis` with test iPhones registered, and GitHub Pages
set to GitHub Actions. Configure the `github-pages` environment to allow the
pull request deployment refs.

| Repository secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE_P12` | Base64 Apple Distribution certificate and private key |
| `APPLE_CERTIFICATE_PASSWORD` | Certificate export password |
| `APPLE_PROVISIONING_PROFILE` | Base64 Ad Hoc profile |
| `APPLE_TEAM_ID` | Apple Developer team identifier |
| `NTFY_TOPIC` | Optional notification topic |

The workflow skips signing and publishing until the four required secrets
are configured. See the [build and publish pipeline](ci/README.md).

## Enabling App Store / TestFlight releases

Create an App Store Connect record for `com.julesseg.healthanalysis` and an
App Store Connect API key with the App Manager role. Configure
`APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, and
`APP_STORE_CONNECT_KEY_P8` alongside the Apple Distribution certificate,
its password, and the team ID. The workflow uses automatic provisioning and
runs on a `vX.X.X` tag or a manual release dispatch.

The optional [Paseo dispatcher setup](docs/agents/auto-dispatch.md) uses a
self-hosted Mac runner with separately configured Actions variables.

## Product documentation

- [Product design](docs/design.md)
- [Consolidated specification](docs/spec.md)
- [Native iOS interface design](docs/ui-design.md)
- [Domain glossary](GLOSSARY.md)
- [Native iPhone architecture decision](docs/adr/0001-native-iphone-on-device-analysis.md)
- [Data sources and verification still needed](docs/data-sources.md)
- [Analysis evidence and confidence](docs/analysis-evidence.md)
