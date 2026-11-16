# Health dashboard design

The user confirmed this first-version scope on 2026-11-16. Implementation has not started; the technical validation work below remains necessary.

## Established requirements

- Use Apple Health as the initial candidate for aggregated health data. The user records HRV and sleep with a Garmin Forerunner 965 and transfers Garmin HRV through Livity. Direct Garmin integration may be unnecessary; the coverage and meaning of transferred data remain to be checked.
- Allow the person to select any supported input or combination of inputs and any supported output. Supported means the app can obtain the data and give the requested analysis a meaningful definition; it does not promise access to every HealthKit type.
- Include useful default analyses and allow the app to discover candidate correlations automatically.
- Explore associations with a specific day's behavior and with behavior over the preceding week or month, including possible longer-term associations.
- Support quick manual logging and backdated entries.
- Begin with a native iPhone app for the user's own use, with on-device storage and analysis. A web interface may be considered later.
- Support behavior combinations and adjusted associations involving more than two inputs, including interactions where one input's association with the output varies with another. Individual contributions and interactions are parts of the same multi-input analysis requirement.
- Analyze the full relevant behavior window when exploring longer-term associations. Separate delay controls are not part of the initial design; the user wants intervening behavior included.
- Allow configurable defaults per manually tracked variable, starting from a chosen date. Distinguish defaulted values from explicit entries, retain missing sensor measurements as missing, and require an explicit choice to fill older history with defaults.
- Present automatic discoveries as exploratory patterns with effect size, coverage, uncertainty, and checks against subsequent data. Insufficient evidence is an expected result.
- Keep the existing HRV bridge as the initial candidate source, subject to checking its data.
- Anchor behavior windows to the output's timing. Associate overnight sleep with its wake date and analyze preceding behavior; exclude behavior that happened after the relevant output.
- Suggest adjustment inputs, show which inputs an analysis used, and allow the user to change them. Report when the available variation and overlapping data cannot distinguish their associations.
- Support custom quantities with units, counts, yes/no values, ratings, and categories as inputs or outputs. Provide presets and reusable quick-log actions.
- Distinguish exact from approximate times in backdated entries.
- Treat Apple Health as read-only. Manual entries and custom tracking belong to this app and are not written back to Apple Health.
- Offer HRV, sleep duration/timing, and resting heart rate as initial output presets, with activity, caffeine, alcohol, medication intake, and subjective stress/energy as suggested inputs. Activate presets according to data availability and the user's tracking choices; all remain editable.
- Run automatic discovery across enabled variables and day/week/month windows, prioritize understandable relationships with adequate data, include adjusted analyses, and refresh as new data arrives. Present findings inside the app initially.
- Include a confidence index for every analysis using insufficient, low, moderate, and high evidence grades, with an explanation of coverage, defaulted values, uncertainty, and consistency over time. Show effect size separately. The [evidence constraints](analysis-evidence.md) record issues the eventual calculation must address; no formula or thresholds have been selected.
- Defer export, restore, and CSV export from the initial scope.
- Distinguish the behavior window, initially one, seven, or thirty days, from the historical analysis period. Default the analysis period to the full usable history of the selected inputs and output, with shorter periods selectable. Start when the required variables can first be analyzed together, allowing for the behavior window's lookback; show the actual overlapping coverage and gaps.
- Select a preferred source per metric, make the choice visible and editable, retain source identity, and prevent duplicate records from being counted twice. Begin with the Garmin/Livity HRV series, subject to the source checks below.

## Accepted architecture

See [Native iPhone app with on-device analysis](adr/0001-native-iphone-on-device-analysis.md).

## Technical validation before implementation

- Livity's transferred HRV measure, timestamps, duplicate handling, and historical coverage. See [data sources](data-sources.md).
- Specify and validate estimation methods for the supported variable types, individual contributions, and interactions; account for dependent observations and automatic searches.
- Define defensible confidence-grade criteria and insufficient-evidence rules. No grade is a calibrated probability of causation.
- Specify exact window boundaries for each output type and handling of time zones, travel, approximate times, and partial coverage.
- Define identity, deduplication, and correction handling for imported records and local edits.
- Map the initial presets to supported HealthKit data types and actual available coverage.
- Bound the automatic search and schedule refreshes within iOS execution limits.

These are engineering and data-validation tasks, not evidence that the user's stored records or an analysis engine have already been verified.

## Outside the initial scope

- Apple Health writes.
- Export, restore, and CSV export.
- A web interface, custom server, direct Garmin integration, and cross-device app synchronization unless a later concrete need changes the architecture.

## Verified platform constraints

HealthKit access requires an entitled Apple-platform app and permission for the requested data types. A web interface would need an app or export to acquire Apple Health data. Native iOS can use HealthKit directly. See [HealthKit setup](https://developer.apple.com/documentation/healthkit/setting-up-healthkit).

HealthKit supports background change notifications, but reads can be unavailable while the device is locked. The design must not assume continuous background access. See [observer queries](https://developer.apple.com/documentation/healthkit/hkobserverquery) and [database access while locked](https://developer.apple.com/documentation/healthkit/hkerror/code/errordatabaseinaccessible).
