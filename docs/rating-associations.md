# Ordered rating associations

Explore supports a daily rating as an input, adjustment input, or output. The configured tracking name and ordered integer levels carry through the question and its evidence. Each rating has a fixed threshold, the first level at or above the midpoint of its configured bounds. A 1–5 rating compares 3–5 with 1–2. A 2–8 rating compares 5–8 with 2–4. The comparison uses order membership only. The same threshold is used when reopening or refreshing a saved question, independent of the observed values or default history.

Questions involving ratings use the complete preceding day and support a shorter analysis period. They use the existing output anchors. A manual rating output uses completed local days and the input cutoff is the start of its output day. Quantity, count, yes/no, and other rating inputs can be modeled together, including under Account for. Interactions and longer behavior windows are unavailable with a rating in any role.

## Interpretation

- A rating input compares the group at or above its threshold with the group below it, holding other modeled inputs fixed. For a numeric Health output, the estimate is a difference in bpm or minutes. For a count output, the [count model](count-associations.md) estimates a proportional change in expected daily count.
- For a yes/no output, the [yes/no model](binary-associations.md) estimates a percentage-point difference in the probability of Yes for the same two groups.
- A rating output is encoded as a threshold indicator and fitted with the existing [adjusted linear model](adjusted-numeric-associations.md). The estimate is a difference in the probability of meeting the output threshold, expressed in percentage points. The input comparison is a threshold contrast for ratings, one event for counts, 100 mg for milligram quantities, or one configured unit for other quantities.
- The rating-output model is a linear projection of the threshold indicator. The app reports contrasts over the paired history and shows no predicted daily probabilities. A coefficient or interval reflects the unconstrained fit and can extend outside the feasible probability-difference range under weak support or extrapolation. The threshold comparison summarizes two groups, with individual levels retained in the observed evidence. See [Chen and Wooldridge on linear probability models](https://www.bls.gov/osmr/research-papers/2023/ec230090.htm).

## Support and uncertainty

The model requires at least 42 joint days and at least 12 per fitted parameter including the intercept. Each rating needs at least six paired, explicitly recorded days in each threshold group. Variation within one group cannot supply the comparison. Assumed and confirmed defaults enter the fit after the recorded support checks. Results retain the raw levels and effective default dates, and show recorded counts for each group. Other inputs and count outputs retain their existing support checks.

The joint model withholds estimates for collinear inputs, insufficient residual variation, or unusable intervals. It uses the existing calendar-day Bartlett HAC covariance and the 95% critical-value approximation from [Kiefer and Vogelsang, Table I](https://cae.economics.cornell.edu/05-08.pdf). The baseline lag is the greater of seven calendar days and twice the cube root of the paired count rounded up. Linear fits involving ratings also use the [existing residual-dependence screen](caffeine-resting-heart-rate.md#estimate-and-evidence) to widen the interval when dependence is substantial. Count outputs retain the count model's baseline-lag procedure. Each interval applies to an individual contrast.

Longer dependence, trends, confounding, and limited overlap can weaken the results. A usable rating result has at most low confidence. An interval including zero gives uncertain direction for threshold contrasts, with no calibrated practical near-zero band.

## Validation

Application tests exercise a reopened rating history with a 30-point input contrast and a 20-point count adjustment contrast, exact observed and defaulted levels, saved refresh, support confined to one threshold group, and a rating adjustment with a known twofold count association. A deterministic simulation measures interval coverage, bias, and width over 72 trials per scenario with 336 days each, alternating a null and a 20-point contrast. It changes the input group in two-week blocks and uses either independent latent output draws or a latent process that persists with probability 0.8 on each day.

| Output dependence | Contrasts covered | Mean bias |
| --- | ---: | ---: |
| Independent | 65/72 | +0.3 percentage points |
| Persistent | 70/72 | −2.1 percentage points |

The persistent intervals averaged 3.45 times as wide as the independent intervals. The baseline procedure covered 63/72 persistent trials. These results describe the tested scenarios. Other dependence patterns, thresholds, and confidence grades beyond low remain unvalidated.

The native fixture seeds synthetic ratings, edits a past level in the daily log, selects both ratings in Explore, and inspects the named contrast, chart accessibility value, and support labels.
