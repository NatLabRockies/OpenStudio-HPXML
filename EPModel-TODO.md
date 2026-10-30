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
| Open | Object metadata | Replace the temporary adapter with native SDK support; address persistence, cloning/merging, and cleanup before relying on those paths. | A process-local, handle-keyed Ruby store implements `setFeature` and the four typed getters through `ModelObject#additionalProperties`. Repeated object lookups retain metadata, including zone `ObjectType` and `BuildingID`. |

### `resources/location.rb`

| Status | Area | Remaining Work | Current Handling |
| --- | --- | --- | --- |
| Open | Weather file | Revisit the EPW handoff once the SDK's weather-file API or replacement is established. | Skip the old weather-file assignment for EPModel; use `model.getSite` for location fields. EPW handoff also uses `meta_measure.rb`: retain the path through child and parent runners, copy it before runner reset, then pass it to EnergyPlus with `-w`. |
| Open | Calendar year | Replace generic IDD-name-based field access with typed EPModel APIs when available. | Set RunPeriod begin/end years and start weekday here, preserving year-crossing and leap-weather behavior. Schedule year reads are in `schedules.rb`; 3.11 retains `YearDescription.assumedYear`. |

### `resources/schedules.rb`

| Status | Area | Remaining Work | Current Handling |
| --- | --- | --- | --- |
| Open | Schedules | Validate ruleset rule/day-schedule APIs across representative workflows. | The current 4.0 build now initializes `ScheduleRuleset`; the base workflow proceeds beyond schedule creation. |

### `resources/model.rb`

| Status | Area | Remaining Work | Current Handling |
| --- | --- | --- | --- |
| Open | EMS sensors | Retain the setter-based workaround unless EPModel adds a constructor overload that accepts the output-variable name. | EPModel only accepts the model in the constructor, so HPXML calls `setOutputVariableOrMeterName` afterward. OpenStudio 3.11 retains the two-argument constructor; the EPModel workflow proceeds beyond sensor creation. |
| Open | Internal mass definitions | Adapt internal-mass creation to supported EPModel classes. | `InternalMassDefinition` is missing; the EPModel surface check is in `constructions.rb` and skips this type, but internal-mass creation still needs an equivalent API. |

### `resources/geometry.rb`

| Status | Area | Remaining Work | Current Handling |
| --- | --- | --- | --- |
| Open | Space floor area | Adapt the conditioned-space floor-area flag to the supported EPModel API. | Skip `setPartofTotalFloorArea` when `Version::UseEPModel` is true; OpenStudio 3.11 retains the native setter. The EPModel flag remains unsupported. |

### `resources/constructions.rb`

| Status | Area | Remaining Work | Current Handling |
| --- | --- | --- | --- |
| Open | Construction R-value check | Restore construction R-value verification when EPModel provides a native calculation or an equivalent is established. | Skip `check_surface_assembly_rvalue` under EPModel because `ConstructionBase#uFactor` is unavailable; OpenStudio 3.11 retains the native check. |
| Open | Reverse construction | Retain the layer-reversal workaround unless EPModel provides `reverseConstruction`. | Build the EPModel reverse construction from `materials.reverse`; OpenStudio 3.11 uses the native method. |
| Open | Kiva custom blocks | Keep the extensible-group shim aligned with the legacy API, including its limit and material reference behavior. | `epmodel.rb` implements `FoundationKiva#addCustomBlock` using the material, depth, X, and Z fields. The workflow now advances past custom-block creation. |
| Open | Foundation association | Adapt surface-to-Kiva association to a supported EPModel API. | Base input creation now stops at `Surface#setAdjacentFoundation` after assigning the Kiva construction. |

## OpenStudio

### `Model.hpp` and `WeatherFile.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Model namespace | Complete the planned rename from `EPModel` back to `Model`. | Remove the temporary namespace alias after the rename. |
| Open | Weather file | Expose `EPModel::WeatherFile` / `Model#getWeatherFile`, or establish the supported replacement. | The EPW path currently has to be retained outside the model. |

### `Model.hpp`, `YearDescription.hpp`, and `RunPeriod.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Calendar year | Resolve the absence of `Model#getYearDescription`, or establish the supported calendar API. | Calendar setup and schedule year reads currently use RunPeriod fields instead. |
| Open | RunPeriod field access | Expose typed begin/end year setters and confirm the supported start-weekday API. | Calendar setup currently uses generic setters with IDD field names. |

### `SiteGroundTemperatureShallow.hpp` and `SiteGroundTemperatureDeep.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Ground temperatures | Provide bulk `resetAllMonths` / `setAllMonthlyTemperatures` helpers for shallow and deep temperatures, or establish their replacements. | Ruby shims implement the missing helpers using the existing typed monthly setters. |

### `ModelObject.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Object metadata | Resolve the absence of native `additionalProperties` on EPModel objects, confirmed for Site and ThermalZone, or establish an alternative. | A temporary Ruby adapter provides process-local metadata only; it is not native model metadata and does not provide serialization or clone/merge support. |

### `ScheduleRuleset.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Schedules | Confirm native support for ruleset rules and day-schedule operations used by HPXML. | `ScheduleRuleset` initialization succeeds in the current build; the base workflow has advanced beyond schedule creation, but broader API coverage remains to be validated. |

### `EnergyManagementSystemSensor.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | EMS sensor constructor | Add an overload accepting the output-variable name, or establish the setter-based form as the supported API. | The two-argument constructor is unavailable in EPModel; HPXML currently works around this with the model-only constructor and `setOutputVariableOrMeterName`. |

### `Space.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Space floor area | Expose `Space#setPartofTotalFloorArea` or establish the supported replacement. | HPXML skips this flag under EPModel because it is missing in the current binding; OpenStudio 3.11 continues to set it for unconditioned spaces. |

### `InternalMassDefinition.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Internal mass definitions | Expose `EPModel::InternalMassDefinition` or establish the supported internal-mass representation. | HPXML's EPModel surface type check skips the missing class, but `Model.add_internal_mass` still depends on it. |

### `ConstructionBase.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Construction R-value | Expose `ConstructionBase#uFactor` or establish an equivalent calculation API. | HPXML skips assembly R-value validation under EPModel; OpenStudio 3.11 continues to validate it. |

### `Construction.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Reverse construction | Expose `Construction#reverseConstruction` or establish a supported replacement. | HPXML reverses the layer list to build an adjacent-surface construction under EPModel. |

### `src/epmodel/ModelObject/FoundationKiva.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Kiva custom blocks | Expose `FoundationKiva#addCustomBlock` or provide a custom-insulation API for material, depth, and position. | The EPModel declaration is in `src/epmodel/ModelObject/FoundationKiva.hpp` and omits the extensible-list convenience methods. The legacy declaration is in `src/model/FoundationKiva.hpp`; HPXML reproduces its four fields through the EPModel shim. |

### `src/model/Surface.hpp`

| Status | Area | SDK Work Needed | OpenStudio-HPXML Impact |
| --- | --- | --- | --- |
| Open | Foundation association | Expose `Surface#setAdjacentFoundation` or establish the supported EPModel association API. | HPXML assigns each foundation surface to its Kiva object after construction setup; the current binding lacks the setter. |

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