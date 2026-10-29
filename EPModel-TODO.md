# EPModel Compatibility TODOs

`Version::UseEPModel` selects the temporary OpenStudio 4.0 EPModel path when
`OpenStudio::EPModel` is present. When false, retain the OpenStudio 3.11 workflow.
Record each new EPModel-specific workaround or missing API under its owning
project. A workaround does not resolve the underlying SDK gap; track current
handling separately from remaining work.

## OpenStudio-HPXML

| Status | Area | Remaining Work | Current Handling |
| --- | --- | --- | --- |
| Open | Model namespace | Remove the constructor alias in `HPXMLtoOpenStudio/resources/meta_measure.rb` when the SDK returns to the `Model` namespace. | Alias `OpenStudio::Model::Model` to `OpenStudio::EPModel::Model`. |
| Open | Weather file | Revisit the EPW handoff once the SDK's weather-file API or replacement is established. | Skip the old weather-file assignment for EPModel; use `model.getSite` for location fields. Pass the EPW path through child and parent runners, then copy it to a Ruby string before logging resets the runner. Supply it to EnergyPlus with `-w`. |
| Open | Calendar year | Replace generic IDD-name-based field access with typed EPModel APIs when available. | Set RunPeriod Begin Year, End Year, and Day of Week for Start Day directly, preserving year-crossing behavior and leap-weather validation. Schedule calculations branch in place to read Begin Year; 3.11 retains `YearDescription.assumedYear`. |
| Open | Ground temperatures | Adapt the shallow ground-temperature reset to the EPModel API. | No workaround yet. `SiteGroundTemperatureShallow#resetAllMonths` is the current 4.0 baseline blocker. |

## OpenStudio

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Model namespace | Complete the planned rename from `EPModel` back to `Model`. | Remove the temporary constructor alias after the rename. |
| Open | Weather file | Expose `EPModel::WeatherFile` / `Model#getWeatherFile`, or establish the supported replacement. | The EPW path currently has to be retained outside the model. |
| Open | Calendar year | Resolve the absence of `Model#getYearDescription`, or establish the supported calendar API. | Calendar setup and schedule year reads currently use RunPeriod fields instead. |
| Open | RunPeriod field access | Expose typed begin/end year setters and confirm the supported start-weekday API. | Calendar setup currently uses generic setters with IDD field names. |
| Open | Ground temperatures | Provide `SiteGroundTemperatureShallow#resetAllMonths` or an equivalent reset API. | Blocks the 4.0 baseline after calendar setup. |
| Open | Object metadata | Resolve the absence of `EPModel::Site#additionalProperties`, or establish an alternative. | Site metadata cannot currently hold the EPW path; the runner handoff avoids this dependency. |

## Baseline Checks

```bash
/c/openstudio-3.11.0/bin/openstudio.exe workflow/run_simulation.rb -x workflow/sample_files/base.xml -d -o 1
../OS-build-release-dev-4/Products/openstudio.exe workflow/run_simulation.rb -x workflow/sample_files/base.xml -d -o 1
```