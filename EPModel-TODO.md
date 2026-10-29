# EPModel Compatibility TODOs

`Version::UseEPModel` selects the temporary OpenStudio 4.0 EPModel path when
`OpenStudio::EPModel` is present. When false, retain the OpenStudio 3.11 workflow.
Record each new EPModel-specific workaround or missing API here.

- [ ] Remove the constructor alias in `HPXMLtoOpenStudio/resources/meta_measure.rb`
  when the SDK exposes the new model as `OpenStudio::Model::Model` again.
- [ ] Resolve the missing `EPModel::WeatherFile` and `Model#getWeatherFile` APIs.
  Currently skip the old weather-file assignment for EPModel, retain the existing
  `model.getSite` location setters, and pass the EPW path through the runner for
  EnergyPlus's `-w` argument. Copy the path from child to parent runners and save
  it as a Ruby string before logging resets the runner.
- [ ] Replace `Model#getYearDescription` with the appropriate EnergyPlus calendar
  or run-period fields. This is the current OpenStudio 4.0 baseline blocker.
- [ ] Resolve the missing `EPModel::Site#additionalProperties` API before relying
  on site metadata. The EPW workaround deliberately does not use this API.

## Baseline Checks

```bash
/c/openstudio-3.11.0/bin/openstudio.exe workflow/run_simulation.rb -x workflow/sample_files/base.xml -d -o 1
../OS-build-release-dev-4/Products/openstudio.exe workflow/run_simulation.rb -x workflow/sample_files/base.xml -d -o 1
```