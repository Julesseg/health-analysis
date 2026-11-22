# Health data sources

Public documentation checked on 2026-11-16. No records from the user's devices have been inspected.

## User-reported setup

- A Garmin Forerunner 965 records HRV and sleep.
- [Livity: Sleep & Health Tracker](https://apps.apple.com/us/app/livity-sleep-health-tracker/id6498938838), by Martynas Narijauskas, transfers Garmin HRV into Apple Health.
- Apple Health aggregates additional health data and is the initial ingestion source for this project.

The user confirmed Livity as the bridge. Its [Garmin integration announcement](https://livity-app.com/en/blog/changelog/v4-4-3) names HRV, resting heart rate, sleep stages, daily activities, VO2 max, and stress as supported categories within Livity. Its App Store version 5.2.0 release notes document writing Garmin and Fitbit data to Apple Health after permission is granted. These claims do not establish a complete HealthKit export schema or verify the user's stored records.

## HRV measurement meaning

The [Forerunner 965 manual](https://www8.garmin.com/manuals/webhelp/GUID-0221611A-992D-495E-8DED-1DD448F7A066/EN-US/GUID-9282196F-D969-404D-B678-F48A13D8D0CB.html) describes overnight wrist measurements and a seven-day average for HRV status. Garmin's [HRV Status explanation](https://www.garmin.com/en-GB/garmin-technology/health-science/hrv-status/) identifies its HRV measure as RMSSD and distinguishes the overnight average, five-minute readings, and the highest five-minute average.

HealthKit defines both [`heartRateVariabilitySDNN`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn) and [`heartRateVariabilityRMSSD`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilityrmssd). The RMSSD type requires iOS/iPadOS 27.0 or later according to Apple's [availability documentation](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilityrmssd.md). Do not assume SDNN is the only available HRV type or that Livity necessarily places Garmin RMSSD in it. Establish the actual stored type, source, and original measurement definition before combining series.

Livity's [FAQ](https://www.livity-app.com/en/faq) describes using sleep-window HRV and resting heart rate in its own displays. That does not establish the summary or timestamps exported from Garmin into HealthKit.

Its App Store history mentions automatic Garmin history sync and background syncing, but does not establish exact lookback bounds, per-metric coverage, delivery frequency, or guaranteed background completion. Garmin Connect's own Apple Health integration has separate constraints; do not assign them to Livity's direct integration.

## Sleep duration and timing

- The app reads HealthKit `sleepAnalysis` category samples. Each raw record keeps its HealthKit UUID, category value, absolute interval, saver bundle identifier and name, saver revision, and any time-zone metadata. Anchored additions and deletions reconcile by UUID. A correction can delete the original UUID and add a different one. Sleep episodes are derived again from the resulting records. [HealthKit sleep categories](https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis.md)
- Within each saver bundle, the app takes the union of core, deep, REM, and unspecified asleep intervals. An overlapping explicit awake interval removes that time from the union. In-bed records can legitimately overlap stages and contribute no sleep time. Unknown categories and nonpositive intervals contribute no sleep time. The app derives total asleep duration and timing. Overlapping asleep categories contribute no stage-specific duration.
- Adjacent asleep intervals belong to the same episode when their separation is at most 90 elapsed minutes. Longer interruptions start a separate episode. The rule applies to awake intervals and unrecorded time between asleep intervals. Neither adds to duration. In-bed records do not connect episodes. A day can have multiple episodes, including naps. Data shows each episode separately and counts that wake date once in coverage.
- An episode's start and wake time are the first start and last end of accepted asleep intervals. Duration sums elapsed seconds across those intervals, including across daylight-saving changes. The local Gregorian wake date uses the time-zone metadata on the latest accepted sleep segment with a usable zone. For overlapping metadata on that segment, the interval ending latest takes precedence, then the interval starting latest, then UUID order. Older evidence within the same episode can supply the zone when the last segment has none. If the episode has no usable zone metadata, the app displays the device zone saved on the first sleep import as an assumption. HealthKit time-zone metadata describes object creation and may differ from the zone where sleep occurred. Data displays both times in the resolved wake zone. [HealthKit time-zone metadata](https://developer.apple.com/documentation/healthkit/hkmetadatakeytimezone.md)
- All-sources history shows each saver independently, including competing episodes, and counts the union of wake dates for display. Choosing a preferred source filters episodes and coverage to that saver. Days without episodes between the first and last wake dates count as gaps. A batch of only in-bed, awake, or unsupported records supplies source information but no duration, timing, or wake-date coverage.
- Analysis can read `HealthMeasurementHistory.sleepEpisodes` for elapsed duration, absolute onset, absolute wake time, wake date, zone evidence, and saver identity. Use onset for an onset outcome and wake time for duration or wake-time outcomes when checking which inputs precede the outcome. Resolve competing sources and multiple episodes per date explicitly before building a daily analysis series. The raw stage records remain available under `measurements(for: .sleepAnalysis)`.

## Checks still needed

- Confirm Livity's documented export behavior.
- Compare representative stored values with Garmin's corresponding readings.
- Inspect the saving source, start/end timestamps, measurement units, and number of records per night.
- Establish available history, missing nights, resync duplicates, corrections, and sync freshness.
- Check sleep duration, timing, resting heart rate, and activity coverage in Apple Health before enabling the initial presets.

Public documentation can establish intended behavior. Stored-record checks are needed to establish what the user's installation actually supplies.

## On-device HRV inspection for #10

On a signed iPhone build, request read access under **Data → Health access and sources**. Open **Data → Heart rate variability**, refresh, and open a saving source under each HealthKit type. RMSSD reads require iOS 27 or later. Coverage counts imported records and calendar days with a sample start for each stored type and saver.

Open a sample to inspect the value in milliseconds, its start and end, any recorded time zone, the HealthKit value count, saver identity and revision, available device metadata, and sample UUID and sync identity/version where present. Sample duration and the HealthKit value count describe the saved object. The app marks the original HRV measure and summary as unverified and gates analysis until they are established.

Xcode account and provisioning blocked signed physical verification. The following evidence from the user's installation is still unavailable.

- Which stored type or types Livity writes, the saving bundle and revision, any original-device metadata, and the values and unit reported by the signed app.
- Comparison across representative nights against Garmin's overnight average, five-minute readings, highest five-minute average, and seven-day average, including how HealthKit timestamps, time zones, and records per night relate to those summaries.
- Actual readable history, backfill bounds, gaps, and lag between a Garmin reading and its appearance in Apple Health.
- Whether repeated syncs produce distinct UUIDs for the same reading or whether real corrections change values, sync versions, or UUIDs. Compare the current records before and after a resync or correction where one occurs.

Compare records on the phone. If documenting the verification, record the mapping, scope, and conclusions without copying individual health values, sample identifiers, or screenshots off the device.
