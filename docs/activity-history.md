# Workout and running history

Data shows three tracking variables from workout records in Apple Health.

| Tracking variable | Measure in Core | Included records |
| --- | --- | --- |
| Workout duration | Active seconds reported by HealthKit | Any workout type |
| Running duration | Active seconds reported by HealthKit | Workouts whose top-level activity is running |
| Running distance | Meters | Workout-associated walking/running distance statistics for running workouts, with the stored workout total as a fallback |

HealthKit can compute active duration from workout events, so active seconds can differ from elapsed seconds between start and end. Distance comes from the workout record and its associated statistics. The app does not import the all-day walking/running distance series or split multisport workouts into running segments. [Apple workout duration](https://developer.apple.com/documentation/healthkit/hkworkout/duration) · [Apple workout statistics](https://developer.apple.com/documentation/healthkit/hkworkout/statistics(for:)) · [Apple multisport activities](https://developer.apple.com/documentation/healthkit/dividing-a-healthkit-workout-into-activities)

Each record retains its HealthKit UUID, activity type, absolute start and end, the saving source’s bundle identifier and name, and available version, product, and time-zone metadata. Daily display groups by the workout’s end date in the app’s current calendar and time zone. A workout crossing midnight stays whole. Timed analysis can use the retained interval to assess whether a workout falls in a complete preceding window. The daily total does not establish when within the workout its activity occurred.

## Overlap and coverage

HealthKit UUIDs identify stored objects. A bridge and a watch can save separate objects for the same workout. The app keeps all UUIDs and compares their recorded activity type, exact start and end, active duration, and optional running distance. A match across every field contributes once to the daily total, including when the saving sources differ. This is a conservative app policy based on the measurements available in both records. There is no assumed priority among devices or saving apps. [Apple workout identity and measurements](https://developer.apple.com/documentation/healthkit/hkworkout) · [Apple source revisions](https://developer.apple.com/documentation/healthkit/hksourcerevision)

If the remaining records overlap for a positive interval, the daily totals for the affected workout end dates are unavailable. The exposed source and interval details let the person inspect the overlap and choose a preferred source per tracking variable. The filter applies before matching and overlap detection, and adjacent workouts can both contribute. The app uses neither overlap length nor start-time proximity to infer duplicates, because neither establishes active time or distance within the shared interval.

Missing distance for any included workout makes the distance total unavailable for that day. A distance of zero reported by HealthKit contributes zero. A day with no qualifying workout has no total. Coverage shows the date range, days with imported workouts, days with a usable total, and the count of unrecorded days between the first and latest recorded workout day. Coverage describes the records available for the selected variable and source.

## Refresh

The app requests read access to workouts and to walking/running distance for workout statistics. The workout stream has its own anchor. Each successful refresh commits records, workout UUID deletions, and anchors in the existing local snapshot. Repeating a page or reopening the store preserves identity, and deleting a workout allows a replacement with another UUID. Requesting access again rereads previously visible workout history alongside the anchored changes. A failed read retains previously committed values. Edits to associated distance samples that do not surface a workout change may require requesting access again for the historical reread. The relationship between associated sample updates and workout deltas still needs device validation. [Apple read authorization](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data) · [Apple anchored queries](https://developer.apple.com/documentation/healthkit/hkanchoredobjectquerydescriptor) · [Apple deletion identifiers](https://developer.apple.com/documentation/healthkit/hkdeletedobject)
