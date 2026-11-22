# Numeric interactions

Explore can compare the association for one selected quantity at lower and higher values of another selected quantity. A question can include one interaction pair alongside additional inputs and adjustment inputs. The pair and its direction are part of the saved question. The analysis uses the same output series, complete behavior windows, and selectable history as the adjusted numeric model.

## Estimation

Fit all selected inputs and adjustments together with an intercept and the product of the two interaction quantities, each centered at its median. The medians and the lower and higher levels use paired windows with explicit observations for both quantities on every behavior day. Lower and higher are the values at zero-based positions `floor(n / 4)` and `floor(3n / 4)` of the sorted window totals.

The result gives two estimates for the same change in the focal input, from its lower to higher observed level. One estimate holds the second input at its lower level and the other at its higher level, with the remaining modeled inputs held fixed. A third estimate gives the higher-condition estimate minus the lower-condition estimate. All three are contrasts of the same fit. The interval for their difference uses that contrast's regression scores, which account for the covariance between the condition estimates.

Individual associations remain available from the joint model. For either member of the pair, the individual estimate holds the other member at its observed median. Each of the other modeled inputs retains its adjusted estimate per usual increment.

## Evidence

- Use the adjusted numeric coverage and variation rules, including 12 paired output days per parameter and at least six nonoverlapping windows. The interaction product counts as one additional parameter.
- Require distinct lower and higher levels with sufficient spread across fully recorded windows. Each of the four combinations must have at least five fully recorded windows or 2.5% of the fully recorded history rounded up, whichever is greater. A value counts toward a lower combination at or below the lower level and a higher combination at or above the higher level. The uncertainty calculation accounts for shared behavior days. Other modeled values and defaults can still affect the fit.
- Use the same rank and variance inflation limits as the additive model. A dependent product term identifies its two constituent inputs along with any other affected modeled inputs. Insufficient support, a collinear design, or unusable intervals withholds estimates for the requested model.
- Use the adjusted numeric model's dependence-adjusted intervals for each contrast, including the wider-lag method for overlapping windows. Evidence for an available result is at most low and includes the adjusted model's coverage and default limitations. A change whose full interval lies within ±1 bpm for resting heart rate or ±15 minutes for sleep duration is described as similar across the two displayed conditions. These thresholds describe the displayed contrast.

Application checks use synthetic histories with known condition estimates of 2 bpm and 8 bpm, a null interaction with two 5 bpm estimates, exact and near collinearity in the expanded design, and three observed days in one combination with and without default values. The dependence check uses 64 trials per scenario with 308 civil days, three missing output days per seventeen days, and independent or AR(1) inputs and residuals. The acceptance ranges are at least 56 estimable histories per scenario, 85–99% interval coverage among estimable histories, and a dependent-to-independent average interval-width ratio above 1.25. These checks cover one-day windows and stationary synthetic data.

A separate fixture verifies a known interaction on complete overlapping seven-day windows and checks that shared behavior days limit confidence.
