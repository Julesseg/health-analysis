# Daily log CSV

Log exports its recorded history as a UTF-8, comma-delimited file. Each row describes one custom variable. Date columns use local Gregorian dates in `YYYY-MM-DD` form. Export writes dates in chronological order. Import identifies each date by its header. Quote cells containing commas, double quotes or line breaks with double quotes, and double any quote inside a quoted cell.

```csv
name,type,unit,choices,confirmed_default_dates,approximate_time_dates,2026-03-02,2026-03-05,2026-03-08
Coffee,count,,,2026-03-05,,2,0,
Water,quantity,mL,,,,1500,,1800
Exercise,yes_no,,,,,yes,,no
Migraine severity,rating,,"[""0"",""1"",""2"",""3""]",,,1,,0
Last coffee,time,,,,2026-03-02,14:30,,09:00
```

Coffee was explicitly recorded on March 2. Its zero on March 5 came from confirming the displayed default. The empty March 8 cell supplies no observation. Last coffee was around 14:30 on March 2 and exactly 09:00 on March 8.

## Columns and values

Put the variable definition and optional annotations before the date columns. A file for existing variables can consist of just `name` and dates. Export includes the definitions needed to recreate every row on a fresh installation.

| Column | Meaning |
| --- | --- |
| `name` | Required. Match custom variables by name, ignoring case and surrounding spaces. |
| `type` | Required for new variables. Use one of the six types below. |
| `unit` | Unit for a quantity, required when creating it. |
| `choices` | For a new rating or category, supply a JSON array of distinct, nonempty text labels. The array defines the scale from lowest to highest for ratings. |
| `confirmed_default_dates` | Optional space-separated dates whose values came from confirmed defaults. |
| `approximate_time_dates` | Optional space-separated dates with approximate clock times. |

| Type | Populated date cell |
| --- | --- |
| `quantity` | Decimal in the declared unit, using a decimal point and no grouping separators. |
| `count` | Nonnegative whole number, including zero. |
| `yes_no` | `yes` or `no`. |
| `rating` | One label from the ordered scale. |
| `category` | One label from the allowed choices. |
| `time` | Local 24-hour clock time in `HH:mm` form. |

An empty date cell skips that observation. With no annotations, populated cells are explicit observations and times are exact. Each annotated date must name a populated cell in that row. Only time rows accept an approximation annotation.

## Import

1. Choose a CSV file. Validate its headers, row widths, names, definitions, annotations and values before offering Import. Identify errors by row and, for a day cell, by variable and date. Repeated date headers, duplicate variable rows and names matching multiple existing variables are ambiguous.
2. Match against all custom variables, including archived ones. Supplied definitions must agree with the matched variable. Report an incompatible unit, scale, type or choice set. For a date after a configured last logging day, identify the date and the existing limit so the person can correct the file or adjust the tracking period in Log.
3. For a new variable, require a definition and at least one observation. Start tracking on its earliest populated date with an open end and no configured default. Earlier observations can extend an existing start date without moving the effective date of its configured defaults.
4. Preview new variable names and counts of new observations and replacements. A change to a value, its origin or its time precision counts as a replacement. On Import, save the new variables and observations together. A failed write or cancellation applies none of the file. An identical reimport adds no observations.
5. Preserve each day's review status. A confirmed-default annotation describes the origin of one observation, including when importing it into an unreviewed day.

## Copy prompt

The import page copies instructions the person can paste into their chosen LLM along with their source data. Include the format above, a fictional example and the person's current custom variable names, types, units and choices. Include only definitions from their Log. The prompt should give the following direction:

> Convert my source data into the Daily Log CSV format below. Use one row per variable and one column per local date. Match my existing definitions where they fit. Supply definitions for new variables. Leave missing observations blank and preserve recorded zeros and “no” answers. Mark a default or approximate time only when my source identifies it as such. If a date, unit, scale or value is ambiguous, ask me to clarify before generating the CSV. Once the data is clear, return only the CSV.
