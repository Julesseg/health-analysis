# Caffeine and resting heart rate

This Explore question uses a daily manual caffeine quantity in milligrams and a single resting heart rate series in beats per minute. The person selects which milligram quantity represents their caffeine log. The question stores the quantity ID, output metric and source selection, behavior window, history setting, and time zone. The first version offers one complete preceding day, full usable history, and one input with no adjustment.

## Temporal pairing

- Use the Gregorian calendar in the time zone captured when the Explore builder opens. Manual quantities keep their stored civil-date labels. Imported timestamps are interpreted in that one time zone across the history, including during travel. Dates use calendar boundaries, including 23- and 25-hour days and transitions at midnight.
- Resting heart rate records have start and end timestamps. Use the start as the earliest time represented by the record. The entire local day immediately before the day containing that start is the caffeine window. A daily quantity has day-level precision, so the output day’s caffeine is always excluded, including when the output spans midnight. Consider records whose interval has ended at the time of analysis. HealthKit sources can revise a day’s resting heart rate estimate as they collect more measurements. [Apple’s sample timing](https://developer.apple.com/documentation/healthkit/hksample), [Apple’s resting heart rate definition](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/restingheartrate)
- Use the explicitly selected source, the preferred source in Data, or the sole readable source, in that order. When several sources are readable without a preference, require a choice in Data. Within the chosen series, use the earliest valid record per anchor day, breaking ties by end timestamp and then record ID. This yields one pair per output day and avoids averaging observations from different times or sources.
- A pair requires a finite positive resting heart rate and a finite nonnegative caffeine amount. Use the durable logged value, including explicit zero, or the existing effective default for that input date. Keep the provenance of reviewed defaults. Days before a default takes effect remain unavailable unless older history was explicitly filled. A missing Health measurement leaves the day unpaired.
- Full usable history starts at the first actual pair after the lookback and ends at the last actual pair. The result lists usable output dates, intervening gaps, and output days excluded for lack of an eligible caffeine quantity, including excluded output days outside the usable span. Analysis uses imported history and shows when the latest Health check failed and the result therefore uses earlier imports.

## Estimate and evidence

Fit a linear association with an intercept. Center both variables and scale the input for numerical conditioning. Report the slope as the estimated difference in resting heart rate, in bpm per 100 mg more caffeine. Plot the coefficient and its interval against a zero reference.

Use Bartlett-weighted Newey–West covariance of the regression scores with the residual degrees-of-freedom factor `n / (n - 2)`. With `n` paired days, the maximum lag `q` is the greater of 7 days and `ceil(2 × cubeRoot(n))` days. A pair of scores `d` civil days apart receives weight `1 - d / (q + 1)` for `d ≤ q`. Missing dates preserve spacing between pairs. For the approximate two-sided 95% interval, use the Bartlett 97.5th-percentile critical value from Kiefer and Vogelsang’s Table I, with bandwidth fraction `(q + 1) / n`. Using the number of usable pairs in that fraction is a conservative approximation for gaps. The interval is model-based and addresses serial dependence within the chosen lag. [Newey and West](https://users.ssc.wisc.edu/~behansen/718/NeweyWest1987.pdf), [Kiefer and Vogelsang](https://www.ssc.wisc.edu/~bhansen/718/KieferVogelsang.pdf)

These thresholds are initial operational choices for this question.

| Evidence | Rule |
| --- | --- |
| Insufficient | Fewer than 42 paired days, every paired caffeine input is a default, the middle-half caffeine spread is below 20 mg, or the residuals cannot support a usable interval. The spread is the difference between the sorted amounts at zero-based indices `floor(n/4)` and `floor(3n/4)`. |
| Low | An interval is available, with one or more limitations. Fewer than 90 paired days, under 75% overlap within the usable span, over 25% of paired days using assumed defaults, an interval wider than 2 bpm per 100 mg, or an interval consistent with both zero and differences outside the near-zero band. |
| Moderate | All of the above limitations are absent. |
| High | Reserved for a later policy with independent follow-up evidence. |

The near-zero band is ±1 bpm per 100 mg. This is a descriptive display convention. When the full interval fits within the band, the result describes a precise near-zero association. Otherwise, an interval entirely above or below zero supports higher or lower association wording. An interval spanning zero and reaching outside the band is uncertain. Effect size, interval, and evidence grade are displayed separately.

## Validation and limits

The public application tests include a worked date join across the spring change in Paris, a daylight-saving transition at midnight in São Paulo, a record spanning midnight, confirmed defaults, explicit zero, missing output days, source selection, and a failed Health read. A fixed-seed known-slope test requires error below 0.15 bpm per 100 mg and interval width below 0.4. Fixed-seed null cases distinguish a narrow interval entirely within ±1 bpm from a wide interval spanning zero. Separate fixtures check default-heavy history, defaults without observations, low variation, and inadequate coverage.

In 144 deterministic trials per scenario, the true slopes alternate between 0 and −1.5 bpm per 100 mg. The generator drops three consecutive output days out of every seventeen. Acceptance ranges are 88–99% coverage for each longer history and 85–99% for the short dependent history. The longer dependent intervals must average over 1.35 times the width of the independent intervals.

| Simulated history | Truth inside interval |
| --- | --- |
| 252 days, independent predictor and residuals | 135/144 (93.8%) |
| 252 days, AR(1) predictor and residuals with coefficient 0.8 | 128/144 (88.9%) |
| 52 days, AR(1) predictor and residuals with coefficient 0.8 | 129/144 (89.6%) |

The longer dependent intervals averaged 1.74 times as wide as the independent intervals. The undercoverage in these dependent scenarios is a limit of the approximation. These checks cover stationary synthetic histories with the stated gap pattern and one-day windows. Trends, dependence at longer lags, structural changes, selective missingness, default assumptions, other associated variables, and provider-specific timestamp semantics can still affect interpretation. Overlapping windows require their own validation.
