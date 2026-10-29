# EPModel Compatibility TODOs

`Version::UseEPModel` selects the temporary OpenStudio 4.0 EPModel path when
`OpenStudio::EPModel` is present. When false, retain the OpenStudio 3.11 workflow.
Record each new EPModel-specific workaround or missing API under its owning
project. A workaround does not resolve the underlying SDK gap; track current
handling separately from remaining work.

## OpenStudio-HPXML

| Status | Area | Remaining Work | Current Handling |
| --- | --- | --- | --- |
| Open | Model namespace | Remove the namespace alias in `HPXMLtoOpenStudio/resources/meta_measure.rb` when the SDK returns to the `Model` namespace. | Alias the entire `OpenStudio::Model` namespace to `OpenStudio::EPModel` on the EPModel path. Existing constructor calls resolve to EPModel classes without individual aliases; missing classes and methods still need explicit handling. |
| Open | Weather file | Revisit the EPW handoff once the SDK's weather-file API or replacement is established. | Skip the old weather-file assignment for EPModel; use `model.getSite` for location fields. Pass the EPW path through child and parent runners, then copy it to a Ruby string before logging resets the runner. Supply it to EnergyPlus with `-w`. |
| Open | Calendar year | Replace generic IDD-name-based field access with typed EPModel APIs when available. | Set RunPeriod Begin Year, End Year, and Day of Week for Start Day directly, preserving year-crossing behavior and leap-weather validation. Schedule calculations branch in place to read Begin Year; 3.11 retains `YearDescription.assumedYear`. |
| Open | Ground temperatures | Revisit the per-month workaround if EPModel exposes the bulk helpers. | Use typed monthly setters for shallow and deep temperatures. All 12 values are overwritten, so a separate reset is unnecessary. OpenStudio 3.11 retains `resetAllMonths` and `setAllMonthlyTemperatures`. |
| Open | Geometry | Preserve zone metadata using a supported EPModel API or replacement. | Zone and space constructors work through the namespace alias. `ThermalZone#additionalProperties` is missing when storing `ObjectType` and `BuildingID` in `Geometry.create_space_and_zone`; this is the current 4.0 baseline blocker. |

## OpenStudio

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Model namespace | Complete the planned rename from `EPModel` back to `Model`. | Remove the temporary namespace alias after the rename. |
| Open | Weather file | Expose `EPModel::WeatherFile` / `Model#getWeatherFile`, or establish the supported replacement. | The EPW path currently has to be retained outside the model. |
| Open | Calendar year | Resolve the absence of `Model#getYearDescription`, or establish the supported calendar API. | Calendar setup and schedule year reads currently use RunPeriod fields instead. |
| Open | RunPeriod field access | Expose typed begin/end year setters and confirm the supported start-weekday API. | Calendar setup currently uses generic setters with IDD field names. |
| Open | Ground temperatures | Provide bulk `resetAllMonths` / `setAllMonthlyTemperatures` helpers for shallow and deep temperatures, or establish their replacements. | HPXML currently overwrites all 12 months using the existing typed setters instead of calling the missing bulk helpers. |
| Open | Object metadata | Resolve the absence of `additionalProperties` on EPModel objects, confirmed for Site and ThermalZone, or establish an alternative. | The runner handoff avoids site metadata for the EPW path. Missing zone metadata currently blocks geometry setup and is needed for downstream identification and reporting. |

## Baseline Checks

```bash
/c/openstudio-3.11.0/bin/openstudio.exe workflow/run_simulation.rb -x workflow/sample_files/base.xml -d -o 1
../OS-build-release-dev-4/Products/openstudio.exe workflow/run_simulation.rb -x workflow/sample_files/base.xml -d -o 2
```