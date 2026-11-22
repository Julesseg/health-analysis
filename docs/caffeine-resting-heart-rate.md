# Caffeine, resting heart rate, and sleep duration

The person selects a daily caffeine quantity in milligrams and one output, resting heart rate or sleep duration. The question stores the quantity ID, output metric and source selection, Behavior window, History, and analysis time zone.

## Temporal pairing

- The Behavior window sums caffeine across the complete preceding 1, 7, or 30 days. Step through Gregorian day boundaries in the time zone captured when the Explore builder opens, including 23- and 25-hour days and midnight transitions. Manual quantities retain their stored civil-date labels during travel. Daily caffeine has day-level precision. Exact and approximate clock logs are separate variables and play no role in the sum or its timing.
- Resting heart rate uses the earliest valid completed record in the selected source on each analysis day. The start is the earliest time represented and determines both the day label and the window cutoff. Break ties by end timestamp and then record ID. Exclude the entire start date even when the record spans midnight. HealthKit sources can revise a day’s estimate as they collect more measurements. [Apple’s sample timing](https://developer.apple.com/documentation/healthkit/hksample), [Apple’s resting heart rate definition](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/restingheartrate)
- Sleep duration uses the longest episode derived from records that have ended by analysis time, per recorded Gregorian wake date in the selected source. Break ties by earliest onset and then earliest wake. Duration is elapsed asleep time in hours from the derived episode. The wake timestamp is the duration anchor and the output retains the wake-date label from the episode’s zone evidence. The caffeine cutoff uses the earlier of the onset day in the analysis zone and the wake-date label. This excludes caffeine on the onset day, including any logged after the episode began. Sleep onset and wake clock times would need separately defined outcomes. See [sleep derivation and zone evidence](data-sources.md#sleep-duration-and-timing).
- Use the explicitly selected source, the preferred source in Data, or the sole readable source, in that order. When multiple eligible sources are available, choose a preferred source in Data. One source contributes to a result.
- A pair needs a valid output record and a finite nonnegative caffeine amount for every window day. Use the durable logged value, including explicit zero, or the existing effective default. Preserve daily origins, including reviewed defaults. Dates before the default takes effect need an explicit observation or an explicitly filled default. A missing Health measurement leaves the output day unpaired.
- History limits output dates independently of the behavior lookback. Last 90 days and Last 365 days end on the current day in the analysis zone, inclusive, and can use earlier inputs to complete their first windows. Full usable history starts at the first actual pair and ends at the last. Results show usable dates, gaps inside the usable span, and output dates excluded by incomplete inputs. Distinct behavior days count each input date once. The nonoverlapping-window count is the largest set of paired windows with disjoint behavior dates. It measures shared inputs directly. Temporal dependence can persist even between disjoint windows.
- Analysis uses imported history and shows when the latest Health check failed and the result uses earlier imports.

## Estimate and evidence

Fit a linear association with an intercept. Center both variables and scale the input for numerical conditioning. Report the estimated difference per 100 mg more caffeine in the selected window, in bpm for resting heart rate and minutes for sleep duration. Plot the coefficient and interval against a zero reference.

Use Bartlett-weighted Newey–West covariance of the regression scores with the residual degrees-of-freedom factor `n / (n - 2)`. A pair of scores `d` calendar days apart receives weight `1 - d / (q + 1)` for `d ≤ q`. Missing output days preserve that spacing. The reference critical value uses the two-sided 95% Bartlett approximation from Kiefer and Vogelsang’s Table I, with bandwidth fraction `(q + 1) / n`, where `n` is the number of usable pairs. [Newey and West](https://users.ssc.wisc.edu/~behansen/718/NeweyWest1987.pdf), [Kiefer and Vogelsang](https://www.ssc.wisc.edu/~bhansen/718/KieferVogelsang.pdf)

The baseline lag is the maximum of 7 days, the behavior window minus one day, and `ceil(2 × cubeRoot(n))`. When fitted residual pairs show substantial dependence across 1, 2, 3, 7, 14, or 30 calendar days, also test lags of at least 14 days or twice the behavior window, and at least 21 days, three times the behavior window, or one quarter of the pair count. Cap those extensions at half the pair count minus one while retaining the baseline. The heuristic uses at least 20 residual pairs at a lag and an absolute normalized cross-product above both 0.2 and `3 / sqrt(pair count)`. In affected histories use the widest interval and multiply its half-width by 1.2. The broader lag choices investigate sensitivity to serial dependence, and the margin is an empirical safeguard against the undercoverage observed in development simulations. The app calls this a dependence-adjusted interval because synthetic coverage cannot establish a universal confidence level.

These thresholds are operational choices for these comparisons.

| Evidence | Rule |
| --- | --- |
| Insufficient | Fewer than 42 paired days, fewer than six windows with disjoint behavior dates, no observed caffeine days, a middle-half spread below 20 mg in window totals, or residuals that cannot support an interval. The spread is the difference between the sorted window amounts at zero-based indices `floor(n/4)` and `floor(3n/4)`. The disjoint-window minimum keeps heavily reused short histories from qualifying on pair count alone. |
| Low | An interval is available and the evidence has one or more limits. Shared behavior days, fewer than 90 pairs, under 75% of days paired within the usable span, more than 25% of pairs using at least one assumed day, an interval wider than twice the near-zero reference, or an interval consistent with both zero and larger differences. The cap for overlapping windows reflects the remaining reliance on synthetic calibration. |
| Moderate | All of the above limitations are absent. |
| High | Reserved for a later policy with independent follow-up evidence. |

The descriptive near-zero bands are ±1 bpm and ±15 minutes per 100 mg for resting heart rate and sleep duration, respectively. An interval fully inside the band yields a near-zero finding. Otherwise an interval entirely above or below zero supports directional wording. An interval spanning zero and reaching outside the band is uncertain. Effect size, interval, and evidence grade are displayed separately.

## Validation and limits

Application tests cover the spring clock change in Paris, a midnight daylight-saving transition in São Paulo, an entirely skipped civil date in Apia, a resting heart rate record spanning midnight, travel and unfinished sleep records, explicit zero, reviewed defaults, missing outputs, source selection, and a failed Health read. They exercise all windows and both History cutoffs, including lookback before History begins. A monthly fixture yields 71 pairs but only three disjoint windows and withholds the estimate.

The interval checks use 144 deterministic trials per scenario, with slopes alternating between 0 and −1.5 bpm per 100 mg and three consecutive output days dropped out of every seventeen. Acceptance requires 92–99.5% pooled coverage in each scenario. Weekly and monthly tests also require at least 88% coverage for each true slope, mean absolute slope error below 0.5 bpm per 100 mg, and mean interval width below 2.5. The monthly moving-average errors must more than double the average width of the corresponding independent-error intervals.

| Simulated history | Truth inside interval |
| --- | --- |
| 1-day window, 252 days, independent input and errors | 135/144 (93.8%) |
| 1-day window, 252 days, AR(1) input and errors at 0.8 | 138/144 (95.8%) |
| 1-day window, 52 days, AR(1) input and errors at 0.8 | 136/144 (94.4%) |
| 7-day window, 240 days, independent daily input and errors | 135/144 (93.8%) |
| 7-day window, 240 days, AR(1) daily input and errors at 0.8 | 140/144 (97.2%) |
| 30-day window, 420 days, independent daily input and errors | 135/144 (93.8%) |
| 30-day window, 420 days, independent daily input and 30-day moving-average errors | 138/144 (95.8%) |
| 30-day window, 420 days, AR(1) daily input at 0.9 and errors at 0.95 | 140/144 (97.2%) |

The longer and shorter one-day dependent cases covered 128 and 129 trials, respectively, under #13’s single-lag method. The revised longer dependent intervals averaged 2.53 times as wide as the corresponding independent intervals. With the single-lag method, the 30-day moving-average error and strongest AR(1) cases covered 115 and 112 trials. The revised validation spans these stationary synthetic histories and the stated gap pattern. Trends, longer-range dependence, structural changes, selective missingness, default assumptions, other associated variables, and provider-specific timestamps can still affect interpretation.
