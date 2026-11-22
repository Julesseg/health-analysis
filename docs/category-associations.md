# Category associations

A category input or adjustment compares two explicitly chosen labels. The reference defines the baseline and the comparison defines the direction of the estimated change. A preceding day with a different label excludes its output day from the joint fit. The coverage view distinguishes an excluded label from a missing input and preserves the original category, date, and origin for inspection.

A category output uses a selected event label. Every other output label contributes to the comparison group. The model estimates the change in the odds of the selected label, with the other modeled inputs held fixed. For example, a 50% increase multiplies the odds by 1.5. At a baseline probability of 20%, that multiplier would give a probability of about 27%. The app preserves the original category UUID and label for each observation. The order in tracking settings has no effect on either comparison.

| Question | Model and effect |
| --- | --- |
| Category input or adjustment with resting heart rate or sleep duration | Linear regression. Report the adjusted difference in bpm or minutes between the two input labels. |
| Category input or adjustment with a daily count output | Poisson regression. Report the adjusted proportional change in expected count between the two input labels. |
| Selected category output with category, quantity, or count inputs and adjustments | Bernoulli logistic regression. Report the adjusted proportional change in event odds for a named contrast, one additional count, 100 mg, or one unit of another quantity. |

These questions use complete preceding local days and allow a shorter analysis period. Stored category outputs use completed days and run from the daily log. Interactions and longer behavior windows are unavailable for category questions. Mixing categories with yes/no variables is outside the validated combinations. Automatic discovery remains restricted to its existing numeric model family.

## Evidence and uncertainty

The model uses at least 42 joint days and 12 per parameter, including the intercept. Both selected input levels need at least six recorded days in the joint data. Both output groups need at least six recorded days and at least four per model parameter. Each selected category input level used with a category output also needs six jointly recorded event days and six jointly recorded days with other output labels. These are conservative implementation checks for usable support. The individual other labels can be sparse because they contribute to one pooled comparison. Assumed and confirmed defaults participate in the fit after the recorded support checks. Evidence retains counts by original label, days excluded by the contrast, and the effective date of defaults in the paired values.

The category outcome models log odds with an intercept, then transforms the coefficient and interval using exp(βΔ) − 1. It uses the same calendar-day Bartlett HAC interval procedure as the count model, applied to the influence scores from the Bernoulli likelihood. The lag is the greater of seven calendar days and twice the cube root of paired days rounded up. The joint design checks reject near collinearity. A logistic fit that cannot converge with sufficient information withholds the estimate, including in the tested separated cases. Very extreme predictors can also trip the numerical stability checks. [Albert and Anderson on separation](https://doi.org/10.1093/biomet/71.1.1), [Newey and West on HAC covariance](https://www.nber.org/papers/t0055).

The Bernoulli likelihood and its score-based uncertainty can also support a yes/no output. The selected-category odds contrast and the yes/no probability difference are distinct summaries of that fit. Ordinal ratings retain their own ordered threshold and interpretation.

Usable category results carry low confidence. The estimates describe the selected contrast in the available history. Longer dependence, changes over time, unmeasured inputs, and default use can affect interpretation. The model gives individual intervals. Confidence calibration, wider windows, multinomial estimation, and simultaneous inference across multiple contrasts remain outside the validated scope.

## Verification

Application tests verify a stored count contrast with a known 80% difference and its reciprocal, a known 5 bpm contrast with an infrequent level, and an adjusted category outcome with known odds ratios of 6 and 2. They also exercise a reopened daily log and saved result, a confirmed default, retained labels and exclusions, invalid selections, sparse classes, and separation. The interval simulation uses 60 trials of 336 days per scenario, testing odds ratios of 1 and 3 under independent and persistent outcomes. The persistent scenario carries forward a latent draw with probability 0.8, while input categories can change in seven-day blocks. The tests bound interval coverage and log odds bias and check that intervals widen under persistence. The native fixture covers selecting the roles and labels, reading the displayed odds and interval, and inspecting the paired recorded values.
