# EPModel Compatibility TODOs

`Version::UseEPModel` selects the temporary OpenStudio 4.0 EPModel path when
`OpenStudio::EPModel` is present. When false, retain the OpenStudio 3.11 workflow.
Record each new EPModel-specific workaround or missing API under its owning
project. A workaround does not resolve the underlying SDK gap; track current
handling separately from remaining work.

## OpenStudio-HPXML

| Status | Area | Remaining Work | Current Handling |
| --- | --- | --- | --- |
| Open | Model namespace | Remove the namespace alias in `HPXMLtoOpenStudio/resources/epmodel.rb` when the SDK returns to the `Model` namespace. | The centralized Ruby shim aliases the entire `OpenStudio::Model` namespace to `OpenStudio::EPModel`. Existing constructor calls resolve to EPModel classes without individual aliases; missing classes and methods still need explicit handling. |
| Open | Weather file | Revisit the EPW handoff once the SDK's weather-file API or replacement is established. | Skip the old weather-file assignment for EPModel; use `model.getSite` for location fields. Pass the EPW path through child and parent runners, then copy it to a Ruby string before logging resets the runner. Supply it to EnergyPlus with `-w`. |
| Open | Calendar year | Replace generic IDD-name-based field access with typed EPModel APIs when available. | Set RunPeriod Begin Year, End Year, and Day of Week for Start Day directly, preserving year-crossing behavior and leap-weather validation. Schedule calculations branch in place to read Begin Year; 3.11 retains `YearDescription.assumedYear`. |
| Open | Ground temperatures | Remove the Ruby bulk-helper shims when EPModel provides equivalent native APIs. | Shims implement `resetAllMonths` and `setAllMonthlyTemperatures` using typed monthly setters for shallow and deep temperatures. The original HPXML calls are restored; OpenStudio 3.11 retains its native helpers. |
| Open | Object metadata | Replace the temporary adapter with native SDK support; address persistence, cloning/merging, and cleanup before relying on those paths. | A process-local, handle-keyed Ruby store implements `setFeature` and the four typed getters through `ModelObject#additionalProperties`. Repeated object lookups retain metadata, including zone `ObjectType` and `BuildingID`. |
| Open | Schedules | Adapt ruleset schedule creation to supported EPModel schedule objects or a compatible API. | `OpenStudio::EPModel::ScheduleRuleset` is absent in `Model.add_schedule_ruleset`. This is the current 4.0 baseline blocker. |

## OpenStudio

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Model namespace | Complete the planned rename from `EPModel` back to `Model`. | Remove the temporary namespace alias after the rename. |
| Open | Weather file | Expose `EPModel::WeatherFile` / `Model#getWeatherFile`, or establish the supported replacement. | The EPW path currently has to be retained outside the model. |
| Open | Calendar year | Resolve the absence of `Model#getYearDescription`, or establish the supported calendar API. | Calendar setup and schedule year reads currently use RunPeriod fields instead. |
| Open | RunPeriod field access | Expose typed begin/end year setters and confirm the supported start-weekday API. | Calendar setup currently uses generic setters with IDD field names. |
| Open | Ground temperatures | Provide bulk `resetAllMonths` / `setAllMonthlyTemperatures` helpers for shallow and deep temperatures, or establish their replacements. | Ruby shims implement the missing helpers using the existing typed monthly setters. |
| Open | Object metadata | Resolve the absence of native `additionalProperties` on EPModel objects, confirmed for Site and ThermalZone, or establish an alternative. | A temporary Ruby adapter provides process-local metadata only; it is not native model metadata and does not provide serialization or clone/merge support. |
| Open | Schedules | Provide `ScheduleRuleset` or establish the supported replacement. | Ruleset construction currently blocks the 4.0 baseline after zone and space setup. |

## Temporary Shim Limits

- Shims live in `HPXMLtoOpenStudio/resources/epmodel.rb` and apply only when
	`Version::UseEPModel` is true. Existing native methods are not replaced.
- Metadata is keyed by object handle and retained until the process exits. It is
	not serialized with the model, and clone/merge isolation and handle remapping
	are not implemented. Reusing handles can share metadata unintentionally.
- The metadata adapter implements only the five methods currently called by
	HPXML. Weather-file and calendar workarounds remain explicit branches for now.

## Baseline Checks

```bash
/c/openstudio-3.11.0/bin/openstudio.exe workflow/run_simulation.rb -x workflow/sample_files/base.xml -d -o 1
../OS-build-release-dev-4/Products/openstudio.exe workflow/run_simulation.rb -x workflow/sample_files/base.xml -d -o 2
```