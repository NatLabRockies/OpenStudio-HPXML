# EPModel Compatibility TODOs

`Version::UseEPModel` selects the temporary OpenStudio 4.0 EPModel path when `OpenStudio::EPModel` is present.
When false, retain the OpenStudio 3.11 workflow.
Record each new EPModel-specific workaround or missing API under its owning project.
A workaround does not resolve the underlying SDK gap; track current handling separately from remaining work.

## Baseline Checks

```bash
/c/openstudio-3.11.0/bin/openstudio.exe workflow/run_simulation.rb -x workflow/sample_files/base.xml -d -o 1
../OS-build-release-dev-4-312/Products/openstudio.exe workflow/run_simulation.rb -x workflow/sample_files/base.xml -d -o 2
```

## EPModel API Calls

Unique API calls observed in the `base.xml` input-creation path.
`Yes` means the method is provided natively by EPModel.
A shim is Ruby compatibility code in `resources/epmodel.rb` that keeps an existing call working using other EPModel APIs.
For example, `Surface#setAdjacentFoundation` writes the foundation pointer and boundary-condition field; the `InternalMassDefinition` façade maps calls onto `InteriorPartitionSurface`.
Blank also covers methods not available in EPModel and calls used only by the OpenStudio 3.11 branch, such as `WeatherFile.setWeatherFile`.
Ruby core methods and constructors' internal `initialize` calls are omitted.

| API Method Called | Native EPModel? | File location | Remaining Work / Current Handling |
| --- | --- | --- | --- |
| `AdditionalProperties#getFeatureAsDouble` |  | `resources/epmodel.rb` | Process-local metadata adapter. |
| `AdditionalProperties#getFeatureAsInteger` |  | `resources/epmodel.rb` | Process-local metadata adapter. |
| `AdditionalProperties#getFeatureAsString` |  | `resources/epmodel.rb` | Process-local metadata adapter. |
| `AdditionalProperties#setFeature` |  | `resources/epmodel.rb` | Process-local, handle-keyed metadata; not serialized, and clone/merge isolation and handle remapping are not implemented. Reused handles can share metadata. |
| `AirTerminalSingleDuctUncontrolled.new(model, schedule)` |  | `resources/hvac.rb`, `resources/epmodel.rb` | Shim returns `AirTerminalSingleDuctVAVNoReheat` with minimum flow fraction and fixed minimum flow set to zero. This is a supported substitute, but may differ from the 3.11 uncontrolled terminal behavior. |
| `AirLoopHVAC#addBranchForZone(zone, terminal)` | Yes | `resources/epmodel.rb` | Native EPModel branch operation delegated to by the legacy-name shim. |
| `AirLoopHVAC#multiAddBranchForZone(zone, terminal)` |  | `resources/hvac.rb`, `resources/epmodel.rb` | Shim delegates to EPModel's `addBranchForZone(zone, terminal)`, matching the legacy overload's zone/terminal branch attachment. |
| `Construction#setLayers` | Yes | `resources/model.rb` | |
| `Construction#setName` | Yes | `resources/model.rb` | |
| `Construction.new(model)` | Yes | `resources/model.rb` | |
| `ConvergenceLimits#setMaximumHVACIterations` | Yes | `resources/simcontrols.rb` | |
| `ConvergenceLimits#setMinimumSystemTimestep` | Yes | `resources/simcontrols.rb` | |
| `ElectricEquipment#setEndUseSubcategory` | Yes | `resources/model.rb` | |
| `ElectricEquipment#setFractionLatent` | Yes | `resources/model.rb` | |
| `ElectricEquipment#setFractionLost` | Yes | `resources/model.rb` | |
| `ElectricEquipment#setFractionRadiant` | Yes | `resources/model.rb` | |
| `ElectricEquipment#setName` | Yes | `resources/model.rb` | |
| `ElectricEquipment#setSchedule(schedule)` |  | `resources/model.rb`, `resources/epmodel.rb` | Shim writes the `Schedule Name` object reference. |
| `ElectricEquipment#setSpace(space)` |  | `resources/model.rb`, `resources/epmodel.rb` | Shim writes the `Zone or ZoneList or Space or SpaceList Name` object reference. |
| `ElectricEquipment.new(definition)` |  | `resources/model.rb`, `resources/epmodel.rb` | Shim returns the underlying EPModel ElectricEquipment object held by the definition façade. |
| `ElectricEquipment.new(model)` | Yes | `resources/epmodel.rb` | Creates the object held by the ElectricEquipmentDefinition façade. |
| `ElectricEquipmentDefinition#setDesignLevel` |  | `resources/model.rb`, `resources/epmodel.rb` | Definition façade delegates the design level to the EPModel ElectricEquipment object. |
| `ElectricEquipmentDefinition#setFractionLatent` |  | `resources/model.rb`, `resources/epmodel.rb` | Definition façade delegates to the EPModel ElectricEquipment object. |
| `ElectricEquipmentDefinition#setFractionLost` |  | `resources/model.rb`, `resources/epmodel.rb` | Definition façade delegates to the EPModel ElectricEquipment object. |
| `ElectricEquipmentDefinition#setFractionRadiant` |  | `resources/model.rb`, `resources/epmodel.rb` | Definition façade delegates to the EPModel ElectricEquipment object. |
| `ElectricEquipmentDefinition#setName` |  | `resources/model.rb`, `resources/epmodel.rb` | Definition façade delegates to the EPModel ElectricEquipment object. |
| `ElectricEquipmentDefinition.new(model)` |  | `resources/model.rb`, `resources/epmodel.rb` | Creates the underlying EPModel ElectricEquipment object. |
| `EnergyManagementSystemActuator.new(model_object, component_type, control_type)` | Yes | `resources/model.rb` | EPModel path uses the constructor without a SpaceLoadInstance cast; OpenStudio 3.11 retains its SpaceLoadInstance-specific overload. |
| `EnergyManagementSystemGlobalVariable#name` |  | `resources/airflow.rb`, `resources/epmodel.rb` | Shim returns the ERL variable name from the first extensible group; EPModel's inherited ModelObject name is empty. |
| `EnergyManagementSystemOutputVariable#setEMSProgramOrSubroutineName(program)` |  | `resources/model.rb` | Shim writes the `EMS Program or Subroutine Name` pointer; the EPModel wrapper does not expose the typed relationship setter. |
| `EnergyManagementSystemProgram#addLine(line)` |  | `resources/hvac.rb`, `resources/epmodel.rb` | Shim appends a `ProgramLine` group, removes CR/LF and commas from program text, and stores `!` comments as field comments. |
| `EnergyManagementSystemSensor#setKeyName` | Yes | `resources/model.rb` | |
| `EnergyManagementSystemSensor#setName` | Yes | `resources/model.rb` | |
| `EnergyManagementSystemSensor#setOutputVariableOrMeterName` | Yes | `resources/model.rb` | Used after construction as an overload workaround. |
| `EnergyManagementSystemSensor.new(model)` | Yes | `resources/model.rb` | Uses model-only constructor, then sets the output name because the two-argument overload is unavailable. |
| `EnergyManagementSystemSubroutine#addLine(line)` |  | `resources/airflow.rb`, `resources/epmodel.rb` | Shim appends a `ProgramLine` group, removes CR/LF and commas from program text, and stores `!` comments as field comments. |
| `FanSystemModel#numberofSpeeds` | Yes | `resources/epmodel.rb` | EPModel returns zero when `Number of Speeds` is blank; shim returns the legacy default of one and preserves explicit counts. |
| `FoundationKiva#addCustomBlock(material, depth, x, z)` |  | `resources/constructions.rb` | Implemented with extensible-group field writes in `epmodel.rb`. |
| `FoundationKiva#numExtensibleGroups` | Yes | `resources/epmodel.rb` | Used to enforce the ten-group limit. |
| `FoundationKiva#pushExtensibleGroup` | Yes | `resources/epmodel.rb` | Used by the `addCustomBlock` shim. |
| `FoundationKiva#setInitialIndoorAirTemperature` | Yes | `resources/constructions.rb` | |
| `FoundationKiva#setWallDepthBelowSlab` | Yes | `resources/constructions.rb` | |
| `FoundationKiva#setWallHeightAboveGrade` | Yes | `resources/constructions.rb` | |
| `FoundationKiva.new(model)` | Yes | `resources/constructions.rb` | |
| `FoundationKivaSettings#setDeepGroundBoundaryCondition` | Yes | `resources/constructions.rb` | |
| `FoundationKivaSettings#setDeepGroundDepth` | Yes | `resources/constructions.rb` | |
| `FoundationKivaSettings#setFarFieldWidth` | Yes | `resources/constructions.rb` | |
| `FoundationKivaSettings#setGroundSolarAbsorptivity` | Yes | `resources/constructions.rb` | |
| `FoundationKivaSettings#setGroundSurfaceRoughness` | Yes | `resources/constructions.rb` | |
| `FoundationKivaSettings#setGroundThermalAbsorptivity` | Yes | `resources/constructions.rb` | |
| `FoundationKivaSettings#setMaximumCellGrowthCoefficient` | Yes | `resources/constructions.rb` | |
| `FoundationKivaSettings#setMinimumCellDimension` | Yes | `resources/constructions.rb` | |
| `FoundationKivaSettings#setSimulationTimestep` | Yes | `resources/constructions.rb` | |
| `FoundationKivaSettings#setSoilConductivity` | Yes | `resources/constructions.rb` | |
| `FoundationKivaSettings#setSoilDensity` | Yes | `resources/constructions.rb` | |
| `FoundationKivaSettings#setSoilSpecificHeat` | Yes | `resources/constructions.rb` | |
| `InsideSurfaceConvectionAlgorithm#setAlgorithm` | Yes | `resources/simcontrols.rb` | |
| `InteriorPartitionSurface#setConstruction` | Yes | `resources/epmodel.rb` | |
| `InteriorPartitionSurface#setName` | Yes | `resources/epmodel.rb` | |
| `InteriorPartitionSurface#setPointer` | Yes | `resources/epmodel.rb` | Sets the Space reference. |
| `InteriorPartitionSurface#setSurfaceArea` | Yes | `resources/epmodel.rb` | |
| `InteriorPartitionSurface.new(vertices, model)` | Yes | `resources/epmodel.rb` | Underlying object for the InternalMass compatibility façade. |
| `InternalMass#internalMassDefinition` |  | `resources/constructions.rb` | Returns the façade used for construction assignment. |
| `InternalMass#setName` |  | `resources/model.rb` | Compatibility façade. |
| `InternalMass#setSpace` |  | `resources/model.rb` | Compatibility façade. |
| `InternalMass.new(definition)` |  | `resources/model.rb` | Compatibility façade over `InteriorPartitionSurface`. |
| `InternalMassDefinition#adjacentSurface` |  | `resources/constructions.rb` | Returns an empty optional; EPModel internal masses have no adjacent surface. |
| `InternalMassDefinition#setConstruction` |  | `resources/constructions.rb` | Delegates to `InteriorPartitionSurface#setConstruction`. |
| `InternalMassDefinition#setName` |  | `resources/model.rb` | Delegates to `InteriorPartitionSurface#setName`. |
| `InternalMassDefinition#setSpace` |  | `resources/model.rb` | Writes the EnergyPlus Space reference. |
| `InternalMassDefinition#setSurfaceArea` |  | `resources/model.rb` | Delegates to `InteriorPartitionSurface#setSurfaceArea`. |
| `InternalMassDefinition.new(model)` |  | `resources/model.rb` | Creates an `InteriorPartitionSurface` with placeholder vertices, then sets its explicit area. |
| `MeterCustom#addKeyVarGroup(key, output_variable_or_meter)` |  | `resources/model.rb`, `resources/epmodel.rb` | Shim appends a group with `Key Name` and `Output Variable or Meter Name` fields. |
| `Model#alwaysOffDiscreteSchedule` |  | `resources/meta_measure.rb` | Called only for OpenStudio 3.11 cleanup; EPModel skips synthesizing the unused schedule. |
| `Model#getConvergenceLimits` | Yes | `resources/simcontrols.rb` | |
| `Model#getFoundationKivas` | Yes | `resources/epmodel.rb` | Resolves the typed target for `adjacentFoundation`. |
| `Model#getFoundationKivaSettings` | Yes | `resources/constructions.rb` | |
| `Model#getInsideSurfaceConvectionAlgorithm` | Yes | `resources/simcontrols.rb` | |
| `Model#getObjectsByType` | Yes | `resources/epmodel.rb` | Enumerates generic shading IDD objects for the shading-group shim. |
| `Model#getOutsideSurfaceConvectionAlgorithm` | Yes | `resources/simcontrols.rb` | |
| `Model#getModelObjects` |  | `resources/output.rb`, `resources/epmodel.rb` | Shim delegates to EPModel's `Model#objects`, which returns an Array. |
| `Model#getRunPeriod` | Yes | `resources/location.rb`, `resources/schedules.rb`, `resources/simcontrols.rb` | |
| `Model#getRunPeriodControlDaylightSavingTime` | Yes | `resources/location.rb` | |
| `Model#getScheduleTypeLimitss` | Yes | `resources/model.rb` | |
| `Model#getShadingSurfaceGroups` |  | `resources/geometry.rb`, `resources/epmodel.rb` | Shim wraps generic `OS_ShadingSurfaceGroup` objects in compatibility facades. |
| `Model#getShadowCalculation` | Yes | `resources/simcontrols.rb` | |
| `Model#getSimpleGlazings` | Yes | `resources/model.rb` | |
| `Model#getSimulationControl` | Yes | `resources/simcontrols.rb` | |
| `Model#getSite` | Yes | `resources/location.rb` | |
| `Model#getSiteGroundTemperatureShallow` | Yes | `resources/location.rb` | |
| `Model#getStandardOpaqueMaterials` | Yes | `resources/model.rb` | |
| `Model#getSurfacePropertyExposedFoundationPerimeters` | Yes | `resources/epmodel.rb` | Checks for an existing property before creating one. |
| `Model#getSurfaces` | Yes | `resources/geometry.rb` | |
| `Model#getTimestep` | Yes | `resources/simcontrols.rb` | |
| `Model#toIdfFile` | Yes | `resources/epmodel.rb`, `resources/meta_measure.rb` | Used for direct EPModel export because the legacy ForwardTranslator accepts only OpenStudio Model. See Direct IDF Export Normalization below. |
| `Model#getYearDescription` |  | `resources/location.rb`, `resources/schedules.rb` | Called only when `Version::UseEPModel` is false; EPModel reads/writes year fields through `RunPeriod`. |
| `Model#getZoneCapacitanceMultiplierResearchSpecial` | Yes | `resources/simcontrols.rb` | |
| `Model#objects` | Yes | `resources/model.rb`, `resources/meta_measure.rb` | |
| `Model.new` | Yes | `resources/meta_measure.rb` | |
| `ModelObject#additionalProperties` |  | `resources/epmodel.rb` | Returns the process-local compatibility adapter. |
| `ModelObject#getTarget` | Yes | `resources/epmodel.rb` | Resolves object references in association shims. |
| `ModelObject#iddObject` | Yes | `resources/epmodel.rb`, `resources/location.rb`, `resources/schedules.rb` | Used for generic RunPeriod field access and shim field lookup. |
| `ModelObject#setPointer` | Yes | `resources/epmodel.rb` | Used by relationship shims. |
| `ModelObject#to_AdditionalProperties` |  | `resources/output.rb`, `resources/meta_measure.rb`, `ReportSimulationOutput/measure.rb` | Cast is used only on the OpenStudio 3.11 path; EPModel uses a process-local `additionalProperties` adapter instead of model objects. |
| `ModelObject#to_SpaceLoadInstance` |  | `resources/model.rb` | Used only by the OpenStudio 3.11 actuator path; EPModel exposes no SpaceLoadInstance type or cast. |
| `OptionalFoundationKiva#get` | Yes | `resources/geometry.rb` | |
| `OptionalSchedule#get` | Yes | `resources/constructions.rb` | |
| `OptionalScheduleRuleset#get` | Yes | `resources/constructions.rb` | |
| `OptionalScheduleRuleset#is_initialized` | Yes | `resources/constructions.rb` | |
| `OptionalSurface#get` | Yes | `resources/geometry.rb` | |
| `OptionalSurface#is_initialized` | Yes | `resources/constructions.rb` | |
| `OptionalSurface.new` | Yes | `resources/epmodel.rb` | Empty optional returned by the InternalMass compatibility façade. |
| `OptionalSurfacePropertyExposedFoundationPerimeter.new` | Yes | `resources/epmodel.rb` | Wraps the exposed-perimeter object returned by the Surface shim. |
| `OptionalThermalZone#get` | Yes | `resources/geometry.rb`, `resources/hvac.rb` | |
| `OptionalThermostatSetpointDualSetpoint#get` | Yes | `resources/constructions.rb` | |
| `OptionalThermostatSetpointDualSetpoint#is_initialized` | Yes | `resources/constructions.rb` | |
| `OtherEquipment#setEndUseSubcategory` | Yes | `resources/model.rb` | |
| `OtherEquipment#setFuelType` | Yes | `resources/model.rb` | |
| `OtherEquipment#setName` | Yes | `resources/model.rb` | |
| `OtherEquipment#setSchedule(schedule)` |  | `resources/model.rb`, `resources/epmodel.rb` | Shim writes the `Schedule Name` object reference. |
| `OtherEquipment#setSpace(space)` |  | `resources/model.rb`, `resources/epmodel.rb` | Shim writes the `Zone or ZoneList or Space or SpaceList Name` object reference. |
| `OtherEquipment.new(definition)` |  | `resources/model.rb`, `resources/epmodel.rb` | Shim returns the underlying EPModel OtherEquipment object held by the definition façade. |
| `OtherEquipmentDefinition#setDesignLevel` |  | `resources/model.rb`, `resources/epmodel.rb` | Definition façade delegates the design level to the EPModel OtherEquipment object. |
| `OtherEquipmentDefinition#setFractionLatent` |  | `resources/model.rb`, `resources/epmodel.rb` | Definition façade delegates to the EPModel OtherEquipment object. |
| `OtherEquipmentDefinition#setFractionLost` |  | `resources/model.rb`, `resources/epmodel.rb` | Definition façade delegates to the EPModel OtherEquipment object. |
| `OtherEquipmentDefinition#setFractionRadiant` |  | `resources/model.rb`, `resources/epmodel.rb` | Definition façade delegates to the EPModel OtherEquipment object. |
| `OtherEquipmentDefinition#setName` |  | `resources/model.rb`, `resources/epmodel.rb` | Definition façade delegates to the EPModel OtherEquipment object. |
| `OtherEquipmentDefinition.new(model)` |  | `resources/model.rb`, `resources/epmodel.rb` | Creates the underlying EPModel OtherEquipment object. |
| `Model#getOtherEquipments` | Yes | `resources/hvac.rb` | Counts existing equipment for unique names. |
| `OutsideSurfaceConvectionAlgorithm#setAlgorithm` | Yes | `resources/simcontrols.rb` | |
| `RunPeriod#getInt` | Yes | `resources/schedules.rb` | Generic field-index read of Begin Year. |
| `RunPeriod#iddObject` | Yes | `resources/location.rb`, `resources/schedules.rb` | Retrieves field indices for generic RunPeriod field access. |
| `RunPeriod#setBeginDayOfMonth` | Yes | `resources/simcontrols.rb` | |
| `RunPeriod#setBeginMonth` | Yes | `resources/simcontrols.rb` | |
| `RunPeriod#setEndDayOfMonth` | Yes | `resources/simcontrols.rb` | |
| `RunPeriod#setEndMonth` | Yes | `resources/simcontrols.rb` | |
| `RunPeriod#setInt` | Yes | `resources/location.rb` | Generic field-index writes for Begin/End Year. |
| `RunPeriod#setString` | Yes | `resources/location.rb` | Generic field-index write for Day of Week for Start Day. |
| `RunPeriodControlDaylightSavingTime#setEndDate` | Yes | `resources/location.rb` | |
| `RunPeriodControlDaylightSavingTime#setStartDate` | Yes | `resources/location.rb` | |
| `Schedule#to_ScheduleInterval` |  | `resources/schedules.rb` | Used only when `Version::UseEPModel` is false; EPModel exposes no `ScheduleInterval` type. |
| `Schedule#to_ScheduleRuleset` | Yes | `resources/constructions.rb` | |
| `ScheduleConstant#setName` | Yes | `resources/model.rb` | |
| `ScheduleConstant#setScheduleTypeLimits` | Yes | `resources/model.rb` | |
| `ScheduleConstant#setValue` | Yes | `resources/model.rb` | |
| `ScheduleConstant.new(model)` | Yes | `resources/model.rb` | |
| `ScheduleDay#addValue` | Yes | `resources/model.rb` | |
| `ScheduleDay#setName` | Yes | `resources/model.rb` | |
| `ScheduleDay#values` | Yes | `resources/constructions.rb` | |
| `ScheduleRule#daySchedule` | Yes | `resources/model.rb` | |
| `ScheduleRule#setApplyFriday` | Yes | `resources/model.rb` | |
| `ScheduleRule#setApplyMonday` | Yes | `resources/model.rb` | |
| `ScheduleRule#setApplySaturday` | Yes | `resources/model.rb` | |
| `ScheduleRule#setApplySunday` | Yes | `resources/model.rb` | |
| `ScheduleRule#setApplyThursday` | Yes | `resources/model.rb` | |
| `ScheduleRule#setApplyTuesday` | Yes | `resources/model.rb` | |
| `ScheduleRule#setApplyWednesday` | Yes | `resources/model.rb` | |
| `ScheduleRule#setEndDate` | Yes | `resources/model.rb`, `resources/schedules.rb` | |
| `ScheduleRule#setName` | Yes | `resources/model.rb` | |
| `ScheduleRule#setStartDate` | Yes | `resources/model.rb` | |
| `ScheduleRule.new(schedule)` | Yes | `resources/model.rb` | |
| `ScheduleRuleset#defaultDaySchedule` | Yes | `resources/model.rb` | |
| `ScheduleRuleset#getDaySchedule(date)` | Yes | `resources/constructions.rb` | Used when `Version::UseEPModel` is true; OpenStudio 3.11 retains `getDaySchedules(date, date)[0]`. |
| `ScheduleRuleset#name` | Yes | `resources/model.rb` | |
| `ScheduleRuleset#setName` | Yes | `resources/model.rb` | |
| `ScheduleRuleset.new(model)` | Yes | `resources/model.rb` | |
| `ScheduleTypeLimits#name` | Yes | `resources/model.rb` | |
| `ScheduleTypeLimits#setLowerLimitValue` | Yes | `resources/model.rb` | |
| `ScheduleTypeLimits#setName` | Yes | `resources/model.rb` | |
| `ScheduleTypeLimits#setNumericType` | Yes | `resources/model.rb` | |
| `ScheduleTypeLimits#setUpperLimitValue` | Yes | `resources/model.rb` | |
| `ScheduleTypeLimits.new(model)` | Yes | `resources/model.rb` | |
| `SetpointManagerScheduled#setSchedule(schedule)` | Yes | `resources/epmodel.rb` | Constructor compatibility shim assigns the schedule after creating the model-only object. |
| `SetpointManagerScheduled.new(model, schedule)` |  | `resources/waterheater.rb`, `resources/hvac.rb`, `resources/epmodel.rb` | EPModel constructor shim creates the manager with `model`, then calls `setSchedule(schedule)`; OpenStudio 3.11 uses the native overload. |
| `ShadingSurface#additionalProperties` |  | `resources/geometry.rb`, `resources/epmodel.rb` | Shim reads neighbor azimuth and distance from process-local metadata. |
| `ShadingSurface#setVertices(vertices)` |  | `resources/geometry.rb`, `resources/epmodel.rb` | Shim rewrites vertex extensible groups after transformation. |
| `ShadingSurface#vertices` |  | `resources/geometry.rb`, `resources/epmodel.rb` | Shim reads vertex extensible groups. |
| `ShadingSurfaceGroup#name` |  | `resources/geometry.rb`, `resources/epmodel.rb` | Shim returns the generic group's name string. |
| `ShadingSurfaceGroup#shadingSurfaces` |  | `resources/geometry.rb`, `resources/epmodel.rb` | Shim resolves surfaces whose group-name pointer matches this group. |
| `ShadowCalculation#setMaximumFiguresInShadowOverlapCalculations` | Yes | `resources/simcontrols.rb` | |
| `ShadowCalculation#setShadingCalculationUpdateFrequency` | Yes | `resources/simcontrols.rb` | |
| `SimpleGlazing#name` | Yes | `resources/model.rb` | |
| `SimpleGlazing#setName` | Yes | `resources/model.rb` | |
| `SimpleGlazing#setSolarHeatGainCoefficient` | Yes | `resources/model.rb` | |
| `SimpleGlazing#setUFactor` | Yes | `resources/model.rb` | |
| `SimpleGlazing#solarHeatGainCoefficient` | Yes | `resources/model.rb` | |
| `SimpleGlazing#uFactor` | Yes | `resources/model.rb` | |
| `SimpleGlazing.new(model)` | Yes | `resources/model.rb` | |
| `SimulationControl#setRunSimulationforSizingPeriods` | Yes | `resources/simcontrols.rb` | |
| `Site#setElevation` | Yes | `resources/location.rb` | |
| `Site#setKeepSiteLocationInformation` | Yes | `resources/location.rb` | |
| `Site#setLatitude` | Yes | `resources/location.rb` | |
| `Site#setLongitude` | Yes | `resources/location.rb` | |
| `Site#setName` | Yes | `resources/location.rb` | |
| `Site#setTimeZone` | Yes | `resources/location.rb` | |
| `SiteGroundTemperatureShallow#resetAllMonths` |  | `resources/location.rb` | Compatibility helper delegates to native monthly reset methods. |
| `SiteGroundTemperatureShallow#setAllMonthlyTemperatures` |  | `resources/location.rb` | Compatibility helper delegates to native monthly setters. |
| `Space#floorArea` | Yes | `resources/constructions.rb` | |
| `Space#name` | Yes | `resources/constructions.rb` | |
| `Space#setName` | Yes | `resources/geometry.rb` | |
| `Space#setThermalZone` | Yes | `resources/geometry.rb` | |
| `Space#setVolume` | Yes | `resources/geometry.rb` | |
| `Space#thermalZone` | Yes | `resources/constructions.rb`, `resources/geometry.rb`, `resources/hvac.rb` | |
| `Space.new(model)` | Yes | `resources/geometry.rb` | |
| `StandardOpaqueMaterial#conductivity` | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#density` | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#name` | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#roughness` | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#setConductivity` | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#setDensity` | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#setName` | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#setRoughness` | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#setSolarAbsorptance` | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#setSpecificHeat` | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#setThermalAbsorptance` | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#setThickness` | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#setVisibleAbsorptance` | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#solarAbsorptance` | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#specificHeat` | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#thermalAbsorptance` | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#thickness` | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial.new(model)` | Yes | `resources/model.rb` | |
| `SubSurface#setConstruction` | Yes | `resources/constructions.rb` | |
| `SubSurface#setName` | Yes | `resources/geometry.rb` | |
| `SubSurface#setSubSurfaceType` | Yes | `resources/geometry.rb` | |
| `SubSurface#setSurface` | Yes | `resources/geometry.rb` | |
| `SubSurface#shadingSurfaceGroups` |  | `resources/geometry.rb`, `resources/epmodel.rb` | Shim finds groups whose shaded-object pointer matches this subsurface. |
| `SubSurface#subSurfaceType` | Yes | `resources/epmodel.rb` | Validates allowed types in the incident-solar multiplier constructor shim. |
| `SubSurface.new(vertices, model)` | Yes | `resources/geometry.rb` | |
| `SubSurfaceVector#to_ary` |  | `resources/epmodel.rb` | Converts the native vector to an Array for existing `Array#+` use in `geometry.rb`. |
| `Surface#<=>` | Yes | `resources/geometry.rb` | |
| `Surface#adjacentFoundation` |  | `resources/geometry.rb`, `resources/epmodel.rb` | Shim resolves the stored Kiva handle to a typed optional. |
| `Surface#adjacentSurface` | Yes | `resources/constructions.rb` | |
| `Surface#createAdjacentSurface` | Yes | `resources/geometry.rb` | |
| `Surface#createSurfacePropertyExposedFoundationPerimeter` |  | `resources/constructions.rb` | Shim creates and links the property through `Surface Name`. |
| `Surface#outsideBoundaryCondition` | Yes | `resources/geometry.rb` | |
| `Surface#setAdjacentFoundation(foundation)` |  | `resources/constructions.rb` | Shim sets the Kiva pointer and `OutsideBoundaryCondition`. |
| `Surface#setConstruction` | Yes | `resources/constructions.rb` | |
| `Surface#setName` | Yes | `resources/geometry.rb` | |
| `Surface#setOutsideBoundaryCondition` | Yes | `resources/geometry.rb`, `resources/epmodel.rb` | |
| `Surface#setSpace` | Yes | `resources/geometry.rb` | |
| `Surface#setSunExposure` | Yes | `resources/geometry.rb` | |
| `Surface#setSurfaceType` | Yes | `resources/geometry.rb` | |
| `Surface#setWindExposure` | Yes | `resources/geometry.rb` | |
| `Surface#surfaceType` | Yes | `resources/geometry.rb` | |
| `Surface#tilt` | Yes | `resources/constructions.rb` | |
| `Surface.new(vertices, model)` | Yes | `resources/geometry.rb` | |
| `SurfacePropertyExposedFoundationPerimeter#setExposedPerimeterCalculationMethod` | Yes | `resources/epmodel.rb` | |
| `SurfacePropertyExposedFoundationPerimeter#setTotalExposedPerimeter` | Yes | `resources/epmodel.rb` | |
| `SurfacePropertyExposedFoundationPerimeter.new(model)` | Yes | `resources/epmodel.rb` | Native object constructor used by the Surface shim. |
| `SurfacePropertyIncidentSolarMultiplier#setIncidentSolarMultiplier` | Yes | `resources/epmodel.rb` | Sets the legacy constructor's default value of 1.0. |
| `SurfacePropertyIncidentSolarMultiplier#setIncidentSolarMultiplierSchedule` |  | `resources/constructions.rb`, `resources/epmodel.rb` | Compatibility shim writes the schedule reference. |
| `SurfacePropertyIncidentSolarMultiplier#setSubSurface` |  | `resources/epmodel.rb` | Compatibility shim writes the subsurface reference. |
| `SurfacePropertyIncidentSolarMultiplier.new(model)` | Yes | `resources/epmodel.rb` | Native constructor used by the subsurface overload. |
| `SurfacePropertyIncidentSolarMultiplier.new(subsurface)` |  | `resources/constructions.rb` | Constructor overload supplied by the compatibility shim. |
| `ThermalZone#name` | Yes | `resources/hvac.rb` | |
| `ThermalZone#setMultiplier` | Yes | `resources/geometry.rb` | |
| `ThermalZone#setName` | Yes | `resources/geometry.rb` | |
| `ThermalZone#spaces` |  | `resources/hvac.rb`, `resources/epmodel.rb` | Shim filters `Model#getSpaces` by the Space's typed ThermalZone reference. |
| `ThermalZone#isPlenum` |  | `resources/output.rb`, `resources/epmodel.rb` | Shim checks return and supply plenum objects for a matching ThermalZone reference. |
| `ThermalZone#setSequentialCoolingFractionSchedule(equipment, schedule)` |  | `resources/hvac.rb`, `resources/epmodel.rb` | Shim resolves the zone's `ZoneHVACEquipmentConnections` and delegates to its native equipment-list setter. |
| `ThermalZone#setSequentialHeatingFractionSchedule(equipment, schedule)` |  | `resources/hvac.rb`, `resources/epmodel.rb` | Shim resolves the zone's `ZoneHVACEquipmentConnections` and delegates to its native equipment-list setter. |
| `ThermalZone#setThermostatSetpointDualSetpoint` | Yes | `resources/hvac.rb` | |
| `ThermalZone#setVolume` | Yes | `resources/geometry.rb` | |
| `ThermalZone#thermostatSetpointDualSetpoint` | Yes | `resources/constructions.rb` | |
| `ThermalZone.new(model)` | Yes | `resources/geometry.rb` | |
| `ThermostatSetpointDualSetpoint#coolingSetpointTemperatureSchedule` | Yes | `resources/constructions.rb` | |
| `ThermostatSetpointDualSetpoint#heatingSetpointTemperatureSchedule` | Yes | `resources/constructions.rb` | |
| `ThermostatSetpointDualSetpoint#setCoolingSetpointTemperatureSchedule` | Yes | `resources/hvac.rb` | |
| `ThermostatSetpointDualSetpoint#setHeatingSetpointTemperatureSchedule` | Yes | `resources/hvac.rb` | |
| `ThermostatSetpointDualSetpoint#setName` | Yes | `resources/hvac.rb` | |
| `ThermostatSetpointDualSetpoint#setTemperatureDifferenceBetweenCutoutAndSetpoint` | Yes | `resources/hvac.rb` | |
| `ThermostatSetpointDualSetpoint.new(model)` | Yes | `resources/hvac.rb` | |
| `Timestep#setNumberOfTimestepsPerHour` | Yes | `resources/simcontrols.rb` | |
| `WeatherFile.setWeatherFile(model, epw_file)` |  | `resources/location.rb` | Called only when `Version::UseEPModel` is false. For EPModel, `meta_measure.rb` retains the EPW path through runner reset and passes it to EnergyPlus with `-w`. |
| `YearDescription#assumedYear` |  | `resources/schedules.rb` | Used only on the OpenStudio 3.11 branch; EPModel reads RunPeriod Begin Year instead. |
| `YearDescription#setCalendarYear` |  | `resources/location.rb` | Used only on the OpenStudio 3.11 branch; EPModel writes RunPeriod year fields instead. |
| `ZoneCapacitanceMultiplierResearchSpecial#setHumidityCapacityMultiplier` | Yes | `resources/simcontrols.rb` | |
| `ZoneCapacitanceMultiplierResearchSpecial#setTemperatureCapacityMultiplier` | Yes | `resources/simcontrols.rb` | |

## Direct IDF Export Normalization

`EPModelCompatibility.normalize_workspace` in `resources/epmodel.rb` compensates for behavior normally provided by the legacy ForwardTranslator:

- Adds `GlobalGeometryRules` with the legacy defaults when the object is missing.
- Maps `RoofCeiling` to EnergyPlus `Roof` or `Ceiling` based on envelope boundary conditions.
- Maps `ZoneAveraged` to EnergyPlus `EnclosureAveraged` for People objects.
- Adds missing EMS global declarations referenced by `EnergyManagementSystem:OutputVariable`, except when the name already belongs to a global variable or actuator.
- Fills empty `PlantEquipmentOperationSchemes` with a default heating-load scheme for heating supply components, and adds adiabatic pipes to empty demand-side endpoint branches to match the PlantLoop inlet and outlet nodes.
