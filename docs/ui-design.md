# Interface design

This document describes the intended native interface. Implementation is delivered in slices under spec #2.

## Opening screen

Analysis opens to the person’s saved analyses. Tap a question to see its current result. The add (+) button opens a blank analysis builder directly. V1 omits built-in presets. A separate Discover button searches for strong associations and returns a short list of candidate analyses. Open a candidate in the ordinary result view and save it to the same list as a manually created analysis. Both use the same configuration, result presentation, and refresh behavior. Only tapping Discover starts a search for other relationships.

One tap on Discover starts the search across enabled variables without requiring an outcome selection. Keep the search practical on the iPhone 15 Pro and return only suggestions worth exploring. A search may return none. Unsaved suggestions last for the current visit to Discover. Leaving it keeps only the questions the person explicitly saved.

An explicit Discover request may read categories the person has never used in a saved analysis. Show progress from the start, with a short description of the current stage, such as “Checking available history” or “Comparing patterns.” Use completed counts when the amount of work is known. Keep the Log and saved results usable during the search.

In v1, Discover screens questions with one input and one output. It may sample history and prioritize promising comparisons to keep the search quick, even if that leaves some patterns undiscovered. If the search yields no suggestions, show “No suggestions from this search.” Questions run through the analysis builder use their full eligible history regardless of discovery screening.

## Visual character

Use a native iOS interface with the system's Liquid Glass aesthetic and standard SwiftUI components. Let the system provide typography, spacing, materials, control shapes, navigation, sheets, and transitions. Use semantic system colors and SF Symbols, with one restrained tint. Support system light/dark appearance, Dynamic Type, contrast settings, Reduce Transparency, Reduce Motion, and VoiceOver.

Standard navigation and control layers provide the Liquid Glass appearance; forms, charts, and other content retain readable native surfaces. Follow [Apple's Liquid Glass adoption guidance](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass). Confidence and direction always have text labels; color reinforces meaning.

### Native components

| Area | Standard components |
| --- | --- |
| Top-level navigation | TabView and a NavigationStack for each destination |
| Saved analyses | List and Section, with native navigation links |
| Daily log, analysis builder, settings | Grouped Form and Section |
| Values and choices | TextField, Stepper, Toggle, Picker, and DatePicker as appropriate |
| Actions and presentation | System toolbars, Button, sheets, and native dialogs |
| Analysis charts | Swift Charts marks, axes, selection, and accessibility |

Use standard component styling and layout metrics.

## Reading an analysis

Use one result view for any selection of inputs and output. Format a short summary directly from the method’s estimates, using the selected variable names and units. Formatting depends on the kind of estimate and uses deterministic rules shared across variables. Show the confidence level and any limitation that changes the interpretation alongside the result. Show which inputs were included together. Allow deeper inspection of usable history, defaulted values, and uncertainty.

The interface must preserve the distinction between associations and causal effects. Show the actual dates and number of usable observations alongside the result.

## Navigation

Use two bottom tabs. Analysis is the home for saved questions, the analysis builder and on-demand discovery. Log is the home for entering and revisiting manual daily logs by date.

Apple Health is where the person browses imported measurements. Settings are accessible through a gear button.

### Apple Health sources

Aim to support every Apple Health measurement type the app can read on the person’s iPhone. Preserve each type’s units, timing, and meaning when making it available for analysis. The named measurements in the initial issues are examples of this broader scope.

Read measurement history on demand. Analyze requests only the Apple Health categories used by the selected inputs and output. Refreshing a saved analysis uses the same scope. The person can navigate, edit the Log, and open previously computed results while a read or computation runs. Show when a result is still being prepared. Verify responsiveness on the iPhone 15 Pro when a requested category has a large history.

A page in Settings lists the supported Apple Health categories and lets the person choose one source for each. Resolve sources for a category when an analysis first needs it or the person opens its source setting. Choose the initial source once, using Health’s preference when available, otherwise the contributor with readings on the most distinct days in recent history. Keep the choice until the person changes it. Only this page names the sources.

Use the selected source for the category’s entire history. A gap in that source leaves a gap in the category. Changing the source refreshes affected saved analyses using the new source across their full analysis period.

Each custom variable in the daily Log has its own history. For example, a custom caffeine log and dietary caffeine imported from Apple Health can both be available in the analysis builder, each as a separate variable.

## Building an analysis

The analysis builder uses standard labeled controls for Inputs and Output. Choose one or more inputs from a single list. Every analysis uses the full available history for which the selected variables have usable, aligned observations. When several inputs are selected, estimate each input’s association with the output while accounting for the other selected inputs. Analyze opens the result. Returning preserves the configuration.

Both the Inputs picker and the Output picker include a search text field. Search the supported categories and custom variables by name. Opening or searching a picker uses catalog metadata alone. Categories remain selectable even when their history is empty, sparse, or has never been requested. Evaluate coverage when the person taps Analyze and identify any selected category or overlap that has too little usable history.

When saving, prefill an editable Title field with a plain-language description of the configured question, such as “Is caffeine intake related to sleep duration?” The person can accept it or write their own title. Saving adds the analysis to the Analysis tab under that title, where its result can refresh with new data.

## Chart presentation

Choose the chart from the result the method returns. For example, plot group estimates as points labeled by group, or plot an estimated curve over the supported input range. Show uncertainty around estimates and distinguish adjusted estimates from observed measurements. The curve itself can communicate its shape.

Interaction modeling is deferred.

## Daily tracking form

The Log tab opens with today selected. A horizontally scrollable week strip runs across the top of the page. Tapping a day shows its daily log directly below the strip. The form shows each tracked variable’s saved value or its configured default when there is no saved value.

Browse earlier dates by scrolling the week strip. Leave untouched days unmarked, including days with only assumed defaults. Show a dot for a day with saved edits and a check for a confirmed day. Keep a day confirmed when the person later corrects a value. The strip is the only date navigation control.

Use controls suited to each variable, such as quantities with units, counts, yes/no choices, ratings, categories, and optional time-of-day tracking fields such as last caffeine time. Imported Apple Health measurements remain read-only and are not defaulted by this form. Dates, times, and units follow the person's locale and settings.

Autosave valid field edits as values are entered. Each recorded value, including an explicit zero, is immediately available to analysis. On an unconfirmed day, untouched fields display their defaults and remain missing for analysis. Confirm day makes those displayed defaults eligible as confirmed values.

Use Confirm day for the whole-form review action previously called Save day. It confirms every displayed value, including unchanged defaults, and marks the day as reviewed. Separate saving feedback from review status: changes can be saved while the day remains unreviewed. Date changes and dismissal do not require a save/discard prompt; preserve entered values for their original date.

There is no Unknown option or per-day Unknown override in the manual form; this does not change the treatment of missing imported measurements. Use inline validation for incomplete or invalid input and do not replace a stored valid value with invalid text. Persistence failures retain the entered values and show accurate saving/retry feedback.

## First use

Explain and request Apple Health read access. Granting access leaves measurement history in Apple Health until requested. Offer optional setup for manually tracked variables with editable defaults. Apply manual defaults from their chosen start dates; filling older history remains an explicit choice.

## Refresh and insufficient evidence

On first app use each local day, refresh saved analyses. A dedicated Refresh button on the saved analysis page updates just that analysis. Refreshing a saved analysis reruns its configured relationship over the full eligible history, including new and corrected observations. The result is the current estimate and confidence for that question. V1 omits trend detection and separate follow-up assessments for discoveries.

Show progress while creating or updating an analysis, including when reading the selected measurements and when calculating the result. For an existing analysis, retain the last successful result during refresh and show its update time and updating state. If refresh fails, preserve the result with clear freshness and retry information. A new analysis without a successful result has a loading state rather than an old result from another configuration.

If an analysis lacks usable data or variation, show Insufficient evidence, identify the limiting variable or overlap, and direct the person to Log for manual entries or Settings for Health access and source choices. Distinguish an unavailable estimate from an estimated absence of association.

## Constraints for unavailable data

HealthKit hides read-denial status, so an empty query does not establish that permission was denied or that the person has no measurements. Use neutral availability wording and provide a way to review access and sources. See [authorizing access](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data).

Reads can also fail while HealthKit data is protected on a locked device. A failed refresh does not establish that previous measurements disappeared. See [protecting user privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy). These constraints concern imported data and do not add an Unknown option to the daily form.
