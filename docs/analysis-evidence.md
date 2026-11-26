# Evidence for an analysis

Every analysis must expose a confidence index using insufficient, low, moderate, and high evidence grades, with inspectable reasons. The grade summarizes evidence quality; the statistical method, grade criteria, and thresholds still need to be specified and validated.

## Interpretation constraints

Confidence summarizes support for an analysis's result. Keep it distinct from the association's magnitude, practical importance, and any claim of causation. Distinguish an uncertain estimate from a precise estimate close to zero; detecting no association does not automatically imply strong evidence of absence. A p-value or its complement is not the probability that the association is true. See the [ASA statement on p-values](https://www.amstat.org/asa/files/pdfs/P-ValueStatement.pdf).

Successive daily observations can be dependent. Uncertainty estimates and evidence assessments must account for dependence rather than treating each day as independent information. See [Medrano, Kheddar, and Ramdani's physiological time-series research](https://pmc.ncbi.nlm.nih.gov/articles/PMC11752447/).

An on-demand Discover search compares many candidate relationships. Assessing a selected result as though it were the only comparison overstates evidence. Account for that selection before suggesting a candidate. Saved candidates use the same result and refresh contract as manually configured analyses. See [Simmons, Nelson, and Simonsohn (2011)](https://doi.org/10.1177/0956797611417632).

## Evidence that should be inspectable

- The measured association and its uncertainty.
- Dates, overlapping coverage, and variation of the selected variables. Source names appear only in Settings.
- Explicit observations, confirmed defaults, missing values and approximate entries. Unconfirmed defaults are missing.
- Selected inputs and whether the model can distinguish their associations.
- Temporal dependence and, when screening discovery candidates, the scope of the search.

The chosen grade labels do not determine numerical weights, evidence thresholds, or minimum sample counts. Those require a defined and validated analysis procedure.
