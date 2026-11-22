# Adjusted numeric associations

Explore fits one linear model of resting heart rate or sleep duration using the selected daily quantities and the quantities selected under Account for. Suggestions list other logged quantities. The person chooses which to include. A suggestion describes availability, and selection depends on what is relevant to the question.

The fit uses the same [output anchors and complete preceding windows](caffeine-resting-heart-rate.md#temporal-pairing) as the single-input analysis. Each quantity is totaled over the window and every coefficient uses the same paired output dates. The result carries the configuration, resolved Health source, model identifier, and each modeled quantity's ID, unit, role, and default-day count. The single-milligram analysis retains its model identifier.

## Estimation and evidence

The numeric model is ordinary least squares with an intercept. It centers the outcome and uses a centered, scaled, reorthogonalized QR design. Each contrast reports the estimated difference in bpm for resting heart rate or minutes for sleep duration, per 100 mg or per one unit of another quantity in the window. The other modeled values are held fixed.

The model uses these initial operating thresholds.

- Require at least 42 joint days, 12 joint days per fitted parameter counting the intercept, and six windows with disjoint behavior dates.
- Require each quantity to vary across joint windows and across the subset of windows where every day for that quantity was observed. Use the same middle-half spread convention as the single-milligram analysis. The minimum is 20 mg for milligram quantities and resolvable nonzero spread for quantities with other units.
- Withhold the fit when normalized QR detects a dependent column at a tolerance of `1e-8`, or when a variance inflation factor reaches 20. That factor means the other inputs explain at least 95% of the quantity's centered variation. Identify the affected quantities so the person can revise the question. The selected inputs stay together when the model cannot estimate their separate associations.
- Withhold estimates when the residuals or regression scores cannot support usable intervals.

Uncertainty uses Bartlett-weighted Newey–West scores for each linear contrast, with factor `n / (n - p - 1)` for `p` input columns. The maximum lag is the greater of 7 civil days and `ceil(2 × cubeRoot(n))`. Gaps retain their civil-day spacing. The nominal 95% intervals use the Bartlett critical-value approximation at bandwidth fraction `(lag + 1) / n`. The intervals describe individual contrasts. [Newey and West](https://users.ssc.wisc.edu/~bhansen/718/NeweyWest1987.pdf), [Kiefer and Vogelsang, Table I](https://users.ssc.wisc.edu/~bhansen/718/KieferVogelsang.pdf)

The lag rule above applies to adjusted one-day analyses. For seven- and thirty-day windows, use the [residual dependence screen and wider-lag calibration](caffeine-resting-heart-rate.md#estimate-and-evidence) for each contrast. The app presents dependence-adjusted intervals and shows the maximum lag used.

An available numeric fit has at most low confidence. The result also flags shared behavior days, short or sparse history, frequent defaults, and intervals that include zero and allow larger differences. For an estimate per 100 mg, the near-zero band is ±1 bpm for resting heart rate or ±15 minutes for sleep duration. For other quantities, an interval crossing zero gives an uncertain finding. Trends, longer dependence, missingness, defaults, omitted variables, and the choice of model can affect interpretation.

## Validation and reuse

The application-boundary tests use a reopened synthetic history where the unadjusted caffeine estimate is 6 bpm per 100 mg and its adjusted coefficient is zero. Three other coefficients are known. The tolerance is 0.05 bpm per reported increment, and the intervals must contain the known coefficients. Separate fixtures cover exact and near collinearity in both input orders, limited variation, and default-only quantities.

The serial-dependence check uses 96 trials per scenario with 252 civil days, a three-day gap every seventeen days, and alternating zero and nonzero focal associations. The predefined coverage ranges are 88–99% for independent histories and 86–99% for AR(1) histories, with an average dependent-to-independent interval-width ratio above 1.35.

| Contrast | Independent coverage | AR(1) coverage at 0.8 |
| --- | ---: | ---: |
| Focal input | 92/96 (95.8%) | 86/96 (89.6%) |
| Adjustment input | 94/96 (97.9%) | 91/96 (94.8%) |

The average width ratio was 1.71. These one-day trials show undercoverage for the focal contrast under serial dependence.

The overlapping-window tests use 144 trials per scenario with the same regular gaps, AR(1) daily inputs and errors at 0.86, and true associations specified on complete window totals. The tests require 90–99.5% coverage and mean width below 2 bpm per 100 mg for both monitored contrasts.

| Adjusted window | Focal input coverage | Adjustment coverage |
| --- | ---: | ---: |
| 7 days over 252 calendar days | 141/144 (97.9%) | 140/144 (97.2%) |
| 30 days over 360 calendar days | 136/144 (94.4%) | 136/144 (94.4%) |

`LinearAssociationFit` accepts prepared numeric columns, outputs, civil-day positions, and lag and window lengths. Its contrast takes a vector of differences in the original column units. An expanded design can supply indicator or product columns and evaluate a specified comparison using the same fit and uncertainty calculation. Typed or interaction analyses still need their own encoding, support diagnostics, labeled comparisons, and validation.
