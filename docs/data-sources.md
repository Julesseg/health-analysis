# Health data sources

Public documentation checked on 2026-11-16. No records from the user's devices have been inspected.

## User-reported setup

- A Garmin Forerunner 965 records HRV and sleep.
- [Livity: Sleep & Health Tracker](https://apps.apple.com/us/app/livity-sleep-health-tracker/id6498938838), by Martynas Narijauskas, transfers Garmin HRV into Apple Health.
- Apple Health aggregates additional health data and is the initial ingestion source for this project.

The user confirmed Livity as the bridge. Its [Garmin integration announcement](https://livity-app.com/en/blog/changelog/v4-4-3) names HRV, resting heart rate, sleep stages, daily activities, VO2 max, and stress as supported categories within Livity. Its App Store version 5.2.0 release notes document writing Garmin and Fitbit data to Apple Health after permission is granted. These claims do not establish a complete HealthKit export schema or verify the user's stored records.

## HRV measurement meaning

The [Forerunner 965 manual](https://www8.garmin.com/manuals/webhelp/GUID-0221611A-992D-495E-8DED-1DD448F7A066/EN-US/GUID-9282196F-D969-404D-B678-F48A13D8D0CB.html) describes overnight wrist measurements and a seven-day average for HRV status. Garmin's [HRV Status explanation](https://www.garmin.com/en-GB/garmin-technology/health-science/hrv-status/) identifies its HRV measure as RMSSD and distinguishes the overnight average, five-minute readings, and the highest five-minute average.

HealthKit defines both [`heartRateVariabilitySDNN`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn) and [`heartRateVariabilityRMSSD`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilityrmssd). The RMSSD type requires iOS 27.0 or later according to Apple's [availability documentation](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilityrmssd.md). Do not assume SDNN is the only available HRV type or that Livity necessarily places Garmin RMSSD in it. Establish the actual stored type, source, and original measurement definition before combining series.

Livity's [FAQ](https://www.livity-app.com/en/faq) describes using sleep-window HRV and resting heart rate in its own displays. That does not establish the summary or timestamps exported from Garmin into HealthKit.

Its App Store history mentions automatic Garmin history sync and background syncing, but does not establish exact lookback bounds, per-metric coverage, delivery frequency, or guaranteed background completion. Garmin Connect's own Apple Health integration has separate constraints; do not assign them to Livity's direct integration.

## Checks still needed

- Confirm Livity's documented export behavior.
- Compare representative stored values with Garmin's corresponding readings.
- Inspect the saving source, start/end timestamps, measurement units, and number of records per night.
- Establish available history, missing nights, resync duplicates, corrections, and sync freshness.
- Check the meaning and coverage of sleep duration, timing, resting heart rate and activity when validating those categories for on-demand analysis.

Public documentation can establish intended behavior. Stored-record checks are needed to establish what the user's installation actually supplies.
