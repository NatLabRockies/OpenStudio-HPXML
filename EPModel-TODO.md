# EPModel Compatibility TODOs

`Version::UseEPModel` selects the temporary OpenStudio 4.0 EPModel path when
`OpenStudio::EPModel` is present. When false, retain the OpenStudio 3.11 workflow.
Record each new EPModel-specific workaround or missing API under its owning
project. A workaround does not resolve the underlying SDK gap; track current
handling separately from remaining work.

## OpenStudio-HPXML

### `resources/epmodel.rb`

| Status | Area | Remaining Work | Current Handling |
| --- | --- | --- | --- |
| Open | Model namespace | Remove the namespace alias in `HPXMLtoOpenStudio/resources/epmodel.rb` when the SDK returns to the `Model` namespace. | The centralized Ruby shim aliases the entire `OpenStudio::Model` namespace to `OpenStudio::EPModel`. Existing constructor calls resolve to EPModel classes without individual aliases; missing classes and methods still need explicit handling. |
| Open | Ground temperatures | Remove the Ruby bulk-helper shims when EPModel provides equivalent native APIs. | Shims implement `resetAllMonths` and `setAllMonthlyTemperatures` using typed monthly setters for shallow and deep temperatures. The original HPXML calls are restored; OpenStudio 3.11 retains its native helpers. |
| Open | Object metadata persistence | Replace the process-local store with native typed metadata once EPModel persists it through model serialization. | A process-local, handle-keyed Ruby store implements `setFeature` and the four typed getters through `ModelObject#additionalProperties`. Repeated object lookups retain metadata, including zone `ObjectType` and `BuildingID`. |
| Open | Metadata clone/merge | Define clone/merge handle remapping and cleanup, and test that copied objects do not share metadata and reused handles do not leak values. | The store is keyed by handle and lasts for the process; clone/merge isolation and handle remapping are not implemented. |

### `resources/location.rb`

| Status | Area | Remaining Work | Current Handling |
| --- | --- | --- | --- |
| Open | Weather file | Remove the external EPW-path handoff once EPModel supports an in-model weather-file API. | EPModel skips the old weather-file assignment and uses `model.getSite` for location fields. `meta_measure.rb` retains the EPW path through child and parent runners, copies it before runner reset, and passes it to EnergyPlus with `-w`. |
| Open | Calendar year | Replace generic field-index access for RunPeriod Begin Year, End Year, and Day of Week for Start Day with typed EPModel APIs when exposed; replace the generic Begin Year read in `schedules.rb` as well. | `location.rb` writes the three RunPeriod fields by IDD field index. `schedules.rb` reads Begin Year the same way. Year-crossing and leap-weather behavior are preserved; 3.11 retains `YearDescription.assumedYear`. |

### `resources/schedules.rb`

| Status | Area | Remaining Work | Current Handling |
| --- | --- | --- | --- |
| Open | Schedules | Run `tests/test_schedules.rb` under EPModel; require default/simple schedules, weekday/weekend rules, vacancy and outage periods, and annual-hours checks to pass. | The base workflow confirms `ScheduleRuleset` construction only; the schedule test suite has not been validated under EPModel. |

### `resources/model.rb`

| Status | Area | Remaining Work | Current Handling |
| --- | --- | --- | --- |
| Open | EMS sensors | Replace the model-only constructor plus setter with the output-variable constructor once EPModel exposes that overload. | EPModel currently accepts only the model in the constructor, so HPXML calls `setOutputVariableOrMeterName` afterward. OpenStudio 3.11 retains the two-argument constructor; the EPModel workflow proceeds beyond sensor creation. |
| Open | Internal mass definitions | Implement EPModel internal-mass creation and update `Model.add_internal_mass` and the `constructions.rb` type check to use that representation. | `InternalMassDefinition` is missing; the surface type check skips this type, and internal-mass creation has no EPModel equivalent yet. |

### `resources/geometry.rb`

| Status | Area | Remaining Work | Current Handling |
| --- | --- | --- | --- |
| Open | Space floor area | Restore `setPartofTotalFloorArea(false)` for unconditioned spaces when EPModel exposes an equivalent property; otherwise document the omitted floor-area behavior as an accepted limitation. | The flag is skipped when `Version::UseEPModel` is true; OpenStudio 3.11 retains the native setter. |

### `resources/constructions.rb`

| Status | Area | Remaining Work | Current Handling |
| --- | --- | --- | --- |
| Open | Construction R-value check | Remove the EPModel skip once `ConstructionBase#uFactor` or a validated equivalent is available. | `check_surface_assembly_rvalue` returns early under EPModel because `uFactor` is unavailable; OpenStudio 3.11 retains the native check. |
| Open | Reverse construction | Replace the `materials.reverse` fallback with `reverseConstruction` once EPModel exposes that method, and verify equivalent layer order. | EPModel creates the reverse construction from reversed material layers; OpenStudio 3.11 uses the native method. |
| Open | Kiva custom blocks | Remove the shim once EPModel exposes `FoundationKiva#addCustomBlock`. | `epmodel.rb` writes the material reference, depth, X-position, and Z-position into one extensible group. It accepts up to 10 groups and removes a partially written group if a field write fails. The workflow advances past custom-block creation. |
| Open | Foundation association | Associate each surface with its `FoundationKiva` by setting the foundation object reference and `OutsideBoundaryCondition` to `Foundation` through a supported EPModel API. | Base input creation stops at `Surface#setAdjacentFoundation` after assigning the Kiva construction. |

## OpenStudio

### `Model.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Model namespace | Complete the planned rename from `EPModel` back to `Model`. | Remove the temporary namespace alias after the rename. |
| Open | Weather file | Expose `EPModel::WeatherFile` / `Model#getWeatherFile`, or establish the supported replacement. | EPModel has no `WeatherFile` header or `Model#getWeatherFile`; the EPW path currently has to be retained outside the model. |
| Open | Calendar year | Expose `Model#getYearDescription`, or establish the supported calendar API. | Calendar setup and schedule year reads currently use RunPeriod fields instead. |

### `ParentObject/RunPeriod.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | RunPeriod field access | Expose typed access for `Begin Year`, `End Year`, and `Day of Week for Start Day`, including a typed `Begin Year` read. | `location.rb` writes the three fields and `schedules.rb` reads `Begin Year` through generic IDD field indices. |

### `ModelObject/SiteGroundTemperatureShallow.hpp` and `ModelObject/SiteGroundTemperatureDeep.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Ground temperatures | Provide bulk `resetAllMonths` / `setAllMonthlyTemperatures` helpers for shallow and deep temperatures, or establish their replacements. | Ruby shims implement the missing helpers using the existing typed monthly setters. |

### `ModelObject/ModelObject.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Object metadata persistence | Expose native typed `additionalProperties` access that persists through model serialization. | HPXML currently uses a process-local Ruby adapter; metadata is not serialized with the model. |
| Open | Metadata clone/merge | Define metadata behavior for cloning, merging, handle remapping, and handle reuse. | The current adapter has no clone/merge isolation or handle remapping; reusing handles can share metadata. |

### `Schedule/ScheduleRuleset.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Schedules | Verify EPModel exposes the ruleset, rule date/day-selection, day-value, and rule end-date operations used by `resources/schedules.rb`; add wrappers for any missing operations. | `ScheduleRuleset` construction succeeds, but the EPModel schedule tests have not been run. |

### `ModelObject/EnergyManagementSystemSensor.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | EMS sensor constructor | Add an overload accepting the output-variable name, or establish the setter-based form as the supported API. | The two-argument constructor is unavailable in EPModel; HPXML currently works around this with the model-only constructor and `setOutputVariableOrMeterName`. |

### `PlanarSurfaceGroup/Space.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Space floor area | Expose `Space#setPartofTotalFloorArea` or an equivalent that excludes unconditioned spaces from total floor area. | HPXML skips this flag under EPModel; OpenStudio 3.11 sets it for unconditioned spaces. |

### Missing EPModel class header

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Internal mass definitions | Provide an EPModel internal-mass representation with surface area, space association, and construction assignment, or explicitly mark internal mass unsupported. | No EPModel `InternalMassDefinition` class/header is present; `Model.add_internal_mass` still depends on it. |

### `ConstructionBase/ConstructionBase.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Construction R-value | Expose `ConstructionBase#uFactor` or establish an equivalent calculation API. | HPXML skips assembly R-value validation under EPModel; OpenStudio 3.11 continues to validate it. |

### `LayeredConstruction/Construction.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Reverse construction | Expose `Construction#reverseConstruction` or establish a supported replacement. | HPXML reverses the layer list to build an adjacent-surface construction under EPModel. |

### `ModelObject/FoundationKiva.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Kiva custom blocks | Expose `FoundationKiva#addCustomBlock` or provide a custom-insulation API for material, depth, and position. | `ModelObject/FoundationKiva.hpp` omits the extensible-list convenience methods; HPXML reproduces the four fields through the EPModel shim. |

### `PlanarSurface/Surface.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Foundation association | Expose `Surface#setAdjacentFoundation` or an equivalent that writes the foundation reference and sets `OutsideBoundaryCondition` to `Foundation`. | HPXML assigns each foundation surface to its Kiva object after construction setup; the current binding lacks the setter. |

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
../OS-build-release-dev-4-312/Products/openstudio.exe workflow/run_simulation.rb -x workflow/sample_files/base.xml -d -o 2
```