# Interface design

These interface requirements were agreed through the design interview, including the autosave and native Liquid Glass direction clarified on 2026-11-17. Native screens have not been implemented or visually verified.

## Opening screen

Use this section order: Following, Discovered for you, then Latest measurements. Following holds pinned saved analyses in stable positions, discoveries surface useful exploratory patterns, and current measurements appear as a compact secondary summary.

## Visual character

Use a native iOS interface with the system's Liquid Glass aesthetic and standard SwiftUI components. Let the system provide typography, spacing, materials, control shapes, navigation, sheets, and transitions. Use semantic system colors and SF Symbols, with one restrained tint. Support system light/dark appearance, Dynamic Type, contrast settings, Reduce Transparency, Reduce Motion, and VoiceOver.

Standard navigation and control layers provide the Liquid Glass appearance; forms, charts, and other content retain readable native surfaces. Follow [Apple's Liquid Glass adoption guidance](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass). Confidence and direction always have text labels; color reinforces meaning.

### Native components

| Area | Standard components |
| --- | --- |
| Top-level navigation | TabView and a NavigationStack for each destination |
| Insights and data history | List and Section, with native navigation links |
| Daily log, analysis builder, settings | Grouped Form and Section |
| Values and choices | TextField, Stepper, Toggle, Picker, and DatePicker as appropriate |
| Actions and presentation | System toolbars, Button, sheets, and native dialogs |
| Analysis charts | Swift Charts marks, axes, selection, and accessibility |

Use standard component styling and layout metrics. The earlier HTML sketches establish information hierarchy only; their simulated controls and appearance are not a visual specification for native Liquid Glass.

## Reading an analysis

Lead with a plain-language finding, a chart, effect size, and the confidence grade. Keep limitations that change the interpretation visible beside the finding. Allow deeper inspection of adjustment inputs, usable history, defaulted values, sources, and uncertainty.

The interface must preserve the distinction between associations and causal effects. Keep behavior windows separate from the historical analysis period in both labels and controls.

## Navigation

Use three bottom tabs:

- Insights: discoveries and analyses being followed.
- Explore: build questions and revisit saved analyses.
- Data: measurements, manually tracked daily values, and their history.

A separate Log action opens the daily tracking form. Settings are accessible through a gear button.

## Building an analysis

Explore presents one screen of editable rows: Output, Inputs, Account for, Behavior window, and History. Analyze opens the result; returning preserves the configuration. Saving retains the configuration for refresh with new data. Pinning places it on Insights.

## Chart presentation

Select charts according to the question. Show individual contributions as estimated differences with uncertainty ranges, and interactions as labeled comparisons between conditions. Offer timelines and scatterplots for inspecting underlying measurements. Distinguish adjusted estimates from observed measurements.

## Daily tracking form

Logging works by day. The selected date has a single form containing the different manually tracked variables, initially populated with each variable's configured default when there is no saved value. Reopening a saved day shows its saved values. A date control supports backdating.

Use controls suited to each variable, such as quantities with units, counts, yes/no choices, ratings, categories, and optional time-of-day tracking fields such as last caffeine time. Imported Apple Health measurements remain read-only and are not defaulted by this form. Dates, times, and units follow the person's locale and settings.

Autosave valid field edits as values are entered. These entries are available to analysis without a whole-day confirmation. Untouched values continue using assumed defaults until the day is confirmed.

Use Confirm day for the whole-form review action previously called Save day. It confirms every displayed value, including unchanged defaults, and marks the day as reviewed. Separate saving feedback from review status: changes can be saved while the day remains unreviewed. Date changes and dismissal do not require a save/discard prompt; preserve entered values for their original date.

There is no Unknown option or per-day Unknown override in the manual form; this does not change the treatment of missing imported measurements. Use inline validation for incomplete or invalid input and do not replace a stored valid value with invalid text. Persistence failures retain the entered values and show accurate saving/retry feedback.

## First use

Use a short setup: explain and request Apple Health access, show available measurements and their coverage, then offer manually tracked variables with editable defaults. Manual tracking setup can be skipped so the person can explore existing readable history immediately. Apply manual defaults from their chosen start dates; filling older history remains an explicit choice.

## Refresh and insufficient evidence

For an existing analysis, retain the last successful result during refresh and show its update time and updating state. If refresh fails, preserve the result with clear freshness and retry information. A new analysis without a successful result has a loading state rather than an old result from another configuration.

If an analysis lacks usable data or variation, show Insufficient evidence, explain the specific limitation, and provide access to the relevant data. Distinguish an unavailable estimate from an estimated absence of association.

## Visual evidence

The HTML sketches use fictional values and findings to explore hierarchy. They are not built-app screenshots or verified analyses. The first set compares opening-screen priorities; the second shows Insights, the daily form, and an analysis result in light and dark appearances.

The second set's unsaved-date-change dialog and save-dependent persistence are superseded by autosave and the separate Confirm day action. Its custom HTML styling does not establish Liquid Glass fidelity. Validate the agreed behavior, native components, system appearance, text sizes, and accessibility in a native build before treating the visual implementation as verified.

## Constraints for unavailable data

HealthKit hides read-denial status, so an empty query does not establish that permission was denied or that the person has no measurements. Use neutral availability wording and provide a way to review access and sources. See [authorizing access](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data).

Reads can also fail while HealthKit data is protected on a locked device. A failed refresh does not establish that previous measurements disappeared. See [protecting user privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy). These constraints concern imported data and do not add an Unknown option to the daily form.
