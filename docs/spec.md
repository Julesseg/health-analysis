# Personal iPhone health analysis

Use Apple Health and a personal daily log to explore associations on an iPhone 15 Pro. All storage and analysis happen on the phone. The app reads from Apple Health. The person browses original measurements in Health and manages app-owned values in Log.

## Analysis and Log

- Analysis opens to a single list of saved analyses. Tap + to build a question, Discover to request suggestions, or a saved title to see its current result. Settings opens from a gear button.
- Log opens on today. A horizontally scrollable week strip at the top selects the day whose fields appear below. It is the only date control. An untouched day is unmarked, a day with saved edits has a dot, and a confirmed day has a check. Correcting a value on a confirmed day keeps it confirmed.
- Use native SwiftUI navigation, lists, forms, system styling and charts, accessible text labels, locale-aware dates and units, and system appearance. Target ordinary use on the personal iPhone 15 Pro.

## Measurement catalog and reads

- Aim to support every Apple Health measurement type readable on the device. Describe the meaning, unit, timing, supported roles and daily representation of each measurement. Structured records may yield several meaningful variables. Gate support on a validated interpretation. A readable sleep, activity or other measurement enters the same catalog and can be selected by the same rules. Import preserves the supplied values, components and timestamps. Analysis methods are shared by value type.
- Explain read access on first use. Authorization, opening a picker and searching the catalog do not import measurement history. Optional manual setup can be skipped.
- Both Inputs and Output have a search text field. Search the supported catalog and custom variables by name. Empty, sparse and previously unread categories remain selectable. Distinguish same-named custom and Health variables without displaying contributor names.
- Analyze reads only the selected categories. The same scope applies to a saved analysis refresh. Fetch history on demand, reuse prepared measurements where appropriate, and reconcile additions, corrections and deletions. Duplicate reads must preserve identity. An empty read does not reveal whether access was denied. Failed reads, including on a locked phone, preserve successful prior data.
- A dedicated Settings subpage lists Health categories. Select one source per category. On first need, prefer Health’s preferred contributor if available, otherwise choose the contributor with readings on the most distinct recent days. Preserve the choice until changed. Only Settings names contributors. Use that source throughout the full history, leave its gaps missing, and recompute affected analyses after a switch.
- A custom variable and an imported category have independent identities and histories even if their names and units match. Verify the stored meaning of the user’s Garmin/Livity HRV on a suitable device before claiming support for that bridge.

## Daily logging

- Define custom quantities with units, counts, yes/no fields, ordered ratings, unordered categories and optional times of day. Preserve exact or approximate recalled times and the intended local day across travel and daylight-saving changes.
- Manage custom variables from the Log Categories sheet. Log shows a variable from its tracking start through its optional last logging day, inclusive. The sheet still lists archived variables. Confirm before removing a variable or setting an end date that deletes later entries.
- Show each field’s saved value or applicable configured default. New defaults have effective dates. Applying a default to earlier dates requires an explicit choice and preserves existing entries. A prefilled value alone is missing for analysis.
- Autosave each valid edit against its selected day. An explicitly recorded zero or no counts immediately. Confirm day records every displayed value, including unchanged defaults. Preserve the distinction between a typed entry and a confirmed default. A skipped day adds no observations.
- Keep entries when switching days or leaving the form. Incomplete or invalid input preserves the stored valid value. A failed save retains the edit for retry and accurately shows persistence and review state.

## Building and reading an analysis

- Choose one or more Inputs and exactly one Output. Run the question against all usable aligned history. There is no history or time-window picker, weekly/monthly aggregation control, separate adjustment list, or preset question. Returning from a result preserves the configuration.
- Align the selected observations using their timestamps and interval boundaries. Exclude input behavior occurring after the relevant output. Use the same analysis flow for all supported measurements. Show usable dates and number of observations.
- Choose and validate an estimation method appropriate to the variable types. With multiple inputs, estimate each association accounting for the other selected inputs. Explain when available data cannot distinguish their contributions. Interaction modeling is deferred.
- Use a general result view driven by method output. Deterministically format the estimate in meaningful units, with the selected names and confidence level. A chart can clarify a difference, trend or curve returned by the method. Show uncertainty and distinguish observations from fitted estimates. Results describe associations. No LLM or variable-pair-specific interpretation is needed.
- Grade evidence as insufficient, low, moderate or high, with inspectable reasons. Consider usable overlap, variation, missingness, confirmed defaults, approximation, uncertainty and dependence across days. Distinguish insufficient information, an uncertain estimate and a well-supported small association. Validate methods and grade criteria before reporting them.
- On Save, generate an editable default title from the question. Preserve the configuration and identity when reopening, editing and refreshing. All saved analyses live together and behave alike.

## Discover

- Discover runs only on an explicit request. It may inspect enabled categories that have never appeared in a saved analysis. It returns a short list of strong, adequately supported single-input/single-output associations worth inspecting. It may return none.
- Keep the search responsive and bounded. It may sample stretches of history, eliminate implausible comparisons using date overlap and variation, reuse prepared series and examine a shortlist in depth. Sampling may miss patterns. Check shortlisted analyses against full eligible history and account for selection across the search. A directly requested analysis always uses full eligible history.
- Open a suggestion in the ordinary analysis result view. Saving it keeps the same inputs, output and editable title as a manually built question. Discard unsaved suggestions on leaving Discover. Opening the app, refreshing and logging data never start a discovery scan. V1 does not monitor new trends, run a subsequent-data assessment or maintain a passive feed.

## Progress and refresh

- Show progress for Discover, creating an analysis and updating an analysis. Indicate the stage and use counts when meaningful. Keep navigation and daily logging responsive.
- On the first app use each local day, refresh saved analyses with newly available or corrected data. A dedicated **Refresh** button on each saved analysis page updates just that analysis on demand. A manual refresh does not update its neighbors or run Discover.
- Rerun the same question over all eligible history. Keep its last successful result and timestamp visible while updating. Failed reads or calculations retain that result with accurate freshness and a retry path. A new or changed configuration cannot inherit a different question’s result. Coordinate overlapping work so older completions cannot overwrite newer results.

## Verification and scope

Drive portable behavior through the HealthAnalysisSession used by SwiftUI, with deterministic data at the Health boundary and a reopenable local store for durability. Use hand-checkable histories for date alignment, missing data, corrections, zeros and default provenance. Validate estimates and confidence on known and null associations, including correlated inputs, dependent observations and discovery selection. Use one lean native iPhone journey for meaningful wiring and accessibility checks. Measure responsiveness on a large history and verify HealthKit data semantics on a real device before making claims about personal records.

The first version stays on-device. Apple Health writes, direct Garmin ingestion, a backend, export/restore, device sync, medical recommendations and push notifications are outside scope.
