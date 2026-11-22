# Yes/no associations

A stored yes/no variable can serve as an input, adjustment input, or output. An input compares Yes with No in the complete preceding local day. A stored output uses completed local days and pairs with inputs from before each output day began. Yes/no questions support a shorter analysis period. Interactions and longer behavior windows are unavailable when any modeled variable is yes/no. Either would need an explicit definition and separate validation.

The shared analysis dataset carries the original Yes or No and its origin. Recorded No, an assumed No, and a missing value have distinct meanings. Reviewing a day preserves the effective date of a default. The result and its evidence views expose the actual modeled inputs, output coverage, and paired values with their origins. A stored output does not require Apple Health access.

## Model and effect

For imported resting heart rate or sleep duration, the linear fit reports the adjusted bpm or minute difference for Yes versus No. For a count output, the Poisson fit reports the adjusted proportional change in expected daily count for that comparison.

A yes/no output uses logistic regression with an intercept and all selected inputs and adjustments. For each yes/no input the model predicts the probability of a Yes output with the input set to Yes and to No, while keeping the other input values on each paired day fixed. The reported difference is the average of those paired probability differences, in percentage points. For numeric inputs the comparison increases the value by the usual increment, such as one event or 100 mg. It averages over paired days where both comparison values fit within the explicitly recorded range of that input. Numeric contrasts check each input’s recorded range. Overlap with numeric adjustments can still be limited. These are model-based associations for the paired history. [Marginal standardization for logistic predictions](https://doi.org/10.1093/ije/dyu029)

## Uncertainty and support

The approximate 95% interval applies the delta method to the average contrast, conditional on the paired input profiles. It uses the logistic score and the shared calendar-day Bartlett HAC procedure. The lag is the greater of seven calendar days and twice the cube root of the paired count, rounded up. The result bounds the interval to the possible probability difference of −100 to 100 percentage points. The model withholds estimates if it cannot find a stable fit or estimate uncertainty. Time dependence beyond the lag, unmeasured variables, and reliance on defaults can limit the result. [Newey–West covariance estimation](https://www.nber.org/papers/t0055)

- Require at least 42 paired days and 12 per fitted parameter, including the intercept.
- For a yes/no input, require at least six Yes and six No days among paired recorded values and among all paired values.
- For a yes/no output, require at least six recorded days per input coefficient for **each** output answer. Separate reasons identify a default-only output, a constant recorded answer, and sparse observations.
- When two or more yes/no variables participate, require at least six fully recorded days in every Yes/No combination across those variables. This includes a yes/no output when selected. Defaults can contribute to estimates after the support checks.
- Numeric probability contrasts require at least six recorded starting values that support the reported increase within the recorded range. Collinearity, separation, and a failed interval can also withhold the result.
- A supported yes/no question has low confidence, with reasons for default reliance, sparse overlap, short history, and uncertain direction as applicable. There is no calibrated practical near-zero band for probability differences.

Application tests cover known adjusted associations, a missing combination, sparse and separated outcomes, and default lineage across log and saved-analysis reopening. The interval simulation runs 48 histories per scenario with 336 days per history, including null and 18-percentage-point associations. A two-state probability component has either independent states or lag-one correlation of 0.8. The checks bound bias and empirical coverage and verify wider intervals in the serial scenario. These checks cover the specified preceding-day scenarios and leave stronger dependence, longer windows, and higher confidence grades unvalidated.

The typed catalog and analysis series adapter separate stored values from numeric model inputs. The internal binary event encoding and logistic fit also apply to a genuinely binary event defined from another outcome. Such an event needs a meaningful threshold or comparison, its own support checks, and matching result labels.
