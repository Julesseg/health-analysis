# Native iPhone app with on-device analysis

The first version is a native iPhone app for the user's own use, with storage and analysis on-device. Apple Health is the initial aggregation source, including HRV supplied by the user's existing bridge, whose coverage and measurement meaning still need verification. A web dashboard would require an additional data acquisition path; native access keeps collection, quick logging, and analysis together without requiring a backend. Web access and direct Garmin integration remain possible later if a concrete need emerges.

Apple Health is read-only for this app. App-owned manual entries, custom tracking, and default assumptions remain local; the first version does not export them into Apple Health or offer export and restore.
