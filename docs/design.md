# Product design

Analysis answers personal questions using read-only Apple Health measurements and app-owned daily logs. The two tabs are Analysis and Log. The product contract is in the [specification](spec.md) and screen behavior in the [interface design](ui-design.md).

The app reads history for requested analyses and on-demand discovery. A saved analysis tracks one configuration over all eligible history. Every saved analysis has a dedicated Refresh action.

The [architecture decision](adr/0001-native-iphone-on-device-analysis.md) records the on-device boundary. The [data-source notes](data-sources.md) identify what still needs to be verified about the HRV bridge. The [evidence criteria](analysis-evidence.md) guide method selection and validation.
