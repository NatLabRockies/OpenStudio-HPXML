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
| Open | Internal mass definitions | Replace the compatibility façade once EPModel exposes native internal-mass creation and relationship APIs. | `epmodel.rb` maps the legacy `InternalMassDefinition`/`InternalMass` calls to `InteriorPartitionSurface`, including area, Space reference, and construction. The workflow now advances beyond internal-mass creation. |

### `resources/geometry.rb`

| Status | Area | Remaining Work | Current Handling |
| --- | --- | --- | --- |
| Open | Space floor area | Restore `setPartofTotalFloorArea(false)` for unconditioned spaces when EPModel exposes an equivalent property; otherwise document the omitted floor-area behavior as an accepted limitation. | The flag is skipped when `Version::UseEPModel` is true; OpenStudio 3.11 retains the native setter. |
| Open | Neighbor shading groups | Enumerate and explode neighbor shading surfaces through an EPModel model API. | `geometry.rb` calls the missing `Model#getShadingSurfaceGroups`; the base workflow now stops in `explode_surfaces`. |

### `resources/constructions.rb`

| Status | Area | Remaining Work | Current Handling |
| --- | --- | --- | --- |
| Open | Construction R-value check | Remove the EPModel skip once `ConstructionBase#uFactor` or a validated equivalent is available. | `check_surface_assembly_rvalue` returns early under EPModel because `uFactor` is unavailable; OpenStudio 3.11 retains the native check. |
| Open | Reverse construction | Replace the `materials.reverse` fallback with `reverseConstruction` once EPModel exposes that method, and verify equivalent layer order. | EPModel creates the reverse construction from reversed material layers; OpenStudio 3.11 uses the native method. |
| Open | Kiva custom blocks | Remove the shim once EPModel exposes `FoundationKiva#addCustomBlock`. | `epmodel.rb` writes the material reference, depth, X-position, and Z-position into one extensible group. It accepts up to 10 groups and removes a partially written group if a field write fails. The workflow advances past custom-block creation. |
| Open | Foundation association | Remove the setter/getter shims once EPModel exposes typed `setAdjacentFoundation` and `adjacentFoundation` methods. | `epmodel.rb` writes the foundation handle and `OutsideBoundaryCondition` value, then resolves the target to a typed Kiva optional. The workflow now advances past wall association. |
| Open | Exposed foundation perimeter | Remove the property-creation shim once EPModel exposes the Surface convenience method. | `epmodel.rb` creates the property, links its `Surface Name`, and sets its calculation method and perimeter. The workflow now advances past Kiva slab setup. |
| Open | Kiva initial temperature | Run the focused ruleset test for default-day and rule-override dates. | The rebuilt workflow passed both `getDaySchedule(sim_begin_date)` calls and advanced beyond Kiva initial-temperature setup. |
| Open | Incident solar multiplier | Remove the constructor and schedule-setter shims when EPModel exposes the corresponding relationship APIs. | `epmodel.rb` overloads `new(subsurface)`, sets the subsurface reference and default multiplier, and sets the incident-solar schedule reference. The workflow now advances past window shading setup. |

## OpenStudio

### `Model.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Model namespace | Complete the planned rename from `EPModel` back to `Model`. | Remove the temporary namespace alias after the rename. |
| Open | Weather file | Expose `EPModel::WeatherFile` / `Model#getWeatherFile`, or establish the supported replacement. | EPModel has no `WeatherFile` header or `Model#getWeatherFile`; the EPW path currently has to be retained outside the model. |
| Open | Calendar year | Expose `Model#getYearDescription`, or establish the supported calendar API. | Calendar setup and schedule year reads currently use RunPeriod fields instead. |
| Open | Neighbor shading groups | Expose `Model#getShadingSurfaceGroups` and the typed shading-group/surface objects needed to enumerate neighbor shading. | `geometry.rb` calls the missing collection getter in `explode_surfaces`; the base workflow stops there. |

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
| Open | `ScheduleDayVector` Ruby binding | Directly verify Ruby can index `getDaySchedules` results and add a binding-level regression test if needed. | The ScheduleRuleset SWIG interface imports `ScheduleDayVector` from ScheduleBase, but the latest workflow uses scalar `getDaySchedule` and does not exercise the vector return. |
| Open | Scalar day schedule accessor | Record the focused ruleset test result for `getDaySchedule(date)`, covering both default-day and rule-override dates. | The rebuilt base workflow successfully uses `getDaySchedule` for heating and cooling and proceeds to the shading-group blocker; the focused C++ test result is not recorded here. `getDaySchedules` remains available for range queries. |

### `ModelObject/EnergyManagementSystemSensor.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | EMS sensor constructor | Add an overload accepting the output-variable name, or establish the setter-based form as the supported API. | The two-argument constructor is unavailable in EPModel; HPXML currently works around this with the model-only constructor and `setOutputVariableOrMeterName`. |

### `ModelObject/SurfacePropertyIncidentSolarMultiplier.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Surface and schedule relationships | Expose the `SubSurface`-taking constructor and incident-solar schedule relationship methods, or equivalent typed APIs. | EPModel only exposes construction from `Model` and scalar multiplier fields; `epmodel.rb` supplies the missing relationships for the unchanged HPXML callsite. |

### `PlanarSurfaceGroup/Space.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Space floor area | Expose `Space#setPartofTotalFloorArea` or an equivalent that excludes unconditioned spaces from total floor area. | HPXML skips this flag under EPModel; OpenStudio 3.11 sets it for unconditioned spaces. |

### Missing EPModel class header

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Internal mass definitions | Expose native `InternalMassDefinition`/`InternalMass` APIs, or define `InteriorPartitionSurface` as the supported replacement. | EPModel has no `InternalMassDefinition` header; `epmodel.rb` adapts the legacy helper calls to `InteriorPartitionSurface`. |

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
| Open | Foundation association | Expose `Surface#setAdjacentFoundation` and `Surface#adjacentFoundation`, or equivalent typed APIs for setting and resolving the foundation reference. | HPXML uses both methods; `epmodel.rb` currently shims them using the boundary-condition pointer and typed Kiva collection. |
| Open | Exposed foundation perimeter | Expose `Surface#createSurfacePropertyExposedFoundationPerimeter` or an equivalent Surface convenience API. | HPXML currently creates the exposed-perimeter property through the EPModel shim. |

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