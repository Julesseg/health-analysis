# Adjusted numeric associations

Explore fits one linear model of resting heart rate using the selected daily quantities and the quantities selected under Account for. Suggestions list other logged quantities. The person chooses which to include. A suggestion describes availability, and selection depends on what is relevant to the question.

The fit uses the same complete preceding-day pairing and single Health source as the [resting heart rate analysis](caffeine-resting-heart-rate.md). Every fitted coefficient uses the same days with a value for every selected quantity. The result carries the requested configuration, resolved Health source, model identifier, and each modeled quantity's ID, unit, role, and default-day count. The original single-milligram analysis retains its model identifier and evidence policy.

## Estimation and evidence

The numeric model is ordinary least squares with an intercept. It centers the outcome and uses a centered, scaled, reorthogonalized QR design. For each input, the contrast reports the estimated difference in resting heart rate in bpm per 100 mg or per one unit of another quantity, with the other modeled values held fixed. The increment expresses the slope in the logged unit. Interpret it within the observed history.

The model uses these initial operating thresholds.

- Require at least 42 joint days and 12 joint days per fitted parameter, counting the intercept.
- Require each quantity to vary in both the joint values and their explicitly observed subset. Use the same middle-half spread convention as the single-milligram analysis. The minimum is 20 mg for milligram quantities and resolvable nonzero spread for quantities with other units.
- Withhold the fit when normalized QR detects a dependent column at a tolerance of `1e-8`, or when a variance inflation factor reaches 20. That factor means the other inputs explain at least 95% of the quantity's centered variation. Identify the affected quantities so the person can revise the question. The selected inputs stay together when the model cannot estimate their separate associations.
- Withhold estimates when the residuals or regression scores cannot support usable intervals.

Uncertainty uses Bartlett-weighted Newey–West scores for each linear contrast, with factor `n / (n - p - 1)` for `p` input columns. The maximum lag is the greater of 7 civil days and `ceil(2 × cubeRoot(n))`. Gaps retain their civil-day spacing. The nominal 95% intervals use the Bartlett critical-value approximation at bandwidth fraction `(lag + 1) / n`. The intervals describe individual contrasts. [Newey and West](https://users.ssc.wisc.edu/~bhansen/718/NeweyWest1987.pdf), [Kiefer and Vogelsang, Table I](https://users.ssc.wisc.edu/~bhansen/718/KieferVogelsang.pdf)

An available numeric fit currently has at most low confidence. The result also flags short or sparse history, frequent defaults, and intervals that include zero and allow larger differences. For an estimate per 100 mg, the full interval within ±1 bpm gives a near-zero finding under a descriptive convention. For other quantities, an interval crossing zero gives an uncertain finding because a practical near-zero band has yet to be defined. Trends, longer dependence, missingness, defaults, omitted variables, and the choice of model can affect interpretation.

## Validation and reuse

The application-boundary tests use a reopened synthetic history where the unadjusted caffeine estimate is 6 bpm per 100 mg and its adjusted coefficient is zero. Three other coefficients are known. The tolerance is 0.05 bpm per reported increment, and the intervals must contain the known coefficients. Separate fixtures cover exact and near collinearity in both input orders, limited variation, and default-only quantities.

The serial-dependence check uses 96 trials per scenario with 252 civil days, a three-day gap every seventeen days, and alternating zero and nonzero focal associations. The predefined coverage ranges are 88–99% for independent histories and 86–99% for AR(1) histories, with an average dependent-to-independent interval-width ratio above 1.35.

| Contrast | Independent coverage | AR(1) coverage at 0.8 |
| --- | ---: | ---: |
| Focal input | 92/96 (95.8%) | 86/96 (89.6%) |
| Adjustment input | 94/96 (97.9%) | 91/96 (94.8%) |

The average width ratio was 1.71. These trials show undercoverage for the focal contrast under serial dependence. They cover one-day windows and stationary synthetic histories. Overlapping windows and other data-generating patterns need separate checks.

`LinearAssociationFit` accepts prepared numeric columns, outputs, civil-day positions, and a lag. Its contrast takes a vector of differences in the original column units. An expanded design can supply indicator or product columns and evaluate a specified comparison using the same fit and uncertainty calculation. The [numeric interaction model](numeric-interactions.md) defines the product encoding, support checks, and condition contrasts.
