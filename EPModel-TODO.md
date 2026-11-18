# EPModel Compatibility TODOs

`Version::UseEPModel` selects the temporary OpenStudio 4.0 EPModel path when `OpenStudio::EPModel` is present.
When false, retain the OpenStudio 3.11 workflow.
A shim is Ruby compatibility code that lets existing resource code work around an EPModel API gap using available EPModel APIs.
Record each EPModel API gap and its current workaround in the relevant section of this TODO.
Keep shims in `resources/epmodel.rb` and preserve existing resource calls whenever possible. When EPModel lacks a constructor, provide a compatible class-level `.new` implementation under the expected namespace; if the returned object needs downstream behavior EPModel also lacks, override that method there as well. Do not add a resource-level `Version::UseEPModel` switch merely to work around a missing API. Use resource-level switches only when EPModel requires a genuinely different algorithm or call sequence.
A workaround does not resolve the underlying SDK gap; track current handling separately from remaining work.

## Baseline Checks

```bash
/c/openstudio-3.11.0/bin/openstudio.exe workflow/run_simulation.rb -x workflow/sample_files/base.xml -d -o 1
../OS-build-release-dev-4-312/Products/openstudio.exe workflow/run_simulation.rb -x workflow/sample_files/base.xml -d -o 2
```

Compare the EnergyPlus error files from both runs; a successful simulation alone is not sufficient validation:

```bash
diff -u 1/run/eplusout.err 2/run/eplusout.err
```

Review warning, severe, and fatal message differences. Do not require byte-for-byte equality because the OpenStudio builds may use different EnergyPlus versions.

## Ongoing Base Sample Sweep

Run `workflow/sample_files/base*.xml` in filename order with both builds, using output folder `1` for OpenStudio 3.11 and `2` for EPModel. Compare each pair's `eplusout.err` files. Stop at an EPModel API gap or an unexpected warning, severe error, or fatal error difference, and rerun that sample after addressing the issue.

The EPModel-only EnergyPlus warning that fixed minimum airflow is ignored on VAV terminals is expected and does not stop the sweep.

**Current stop point:** `workflow/sample_files/base-bldgtype-mf-unit-shared-boiler-only-fan-coil-fireplace-elec.xml` — next untested sample; no known blocker.

## Observed EPModel Messages

Successful EPModel base runs emit these nonfatal OpenStudio messages:

- Both shared-boiler water-baseboard samples (with and without combi-tankless DHW) log `BOOST_ASSERT` during OpenStudio input creation when `CoilHeatingWaterBaseboard` getters read unset capacity-per-floor-area and autosized-capacity-fraction fields. These are console diagnostics, not EnergyPlus warnings in `eplusout.err`; both simulations complete with no severe errors.
- A `ZoneHVAC:EquipmentConnections` object has no name, and automatic naming fails. Its origin and impact remain unexplained.
- Plant-side and demand-side branch lists have one branch; EPModel treats it as the equipment branch and adds inlet/outlet branches.
- PlantLoop connector port counts differ from the branch lists; EPModel rebuilds the ports from branch order.

## Direct IDF Export Normalization

`EPModelCompatibility.normalize_workspace` in `resources/epmodel.rb` compensates for behavior normally provided by the legacy ForwardTranslator:

- Adds `GlobalGeometryRules` with the legacy defaults when the object is missing.
- Maps `RoofCeiling` to EnergyPlus `Roof` or `Ceiling` based on envelope boundary conditions.
- Maps `ZoneAveraged` to EnergyPlus `EnclosureAveraged` for People objects.
- Adds missing EMS global declarations referenced by `EnergyManagementSystem:OutputVariable`, except when the name already belongs to a global variable or actuator.
- Fills empty `PlantEquipmentOperationSchemes` with an uncontrolled scheme for vertical ground heat exchangers using the corresponding `GroundHeatExchanger:System` objects, matching the legacy ForwardTranslator; it also adds a default heating-load scheme for heating supply components.
- Adds adiabatic pipes to empty demand-side endpoint branches to match the PlantLoop inlet and outlet nodes. Other cooling and uncontrolled schemes are not synthesized: EPModel `HVACComponent#componentType` currently reports `Heating` for some cooling equipment, so it is not a reliable general classifier.

## EPModel API Calls

Unique API calls observed in EPModel input-creation paths for `workflow/sample_files/base*.xml`.
**Native EPModel?** is `Yes` when EPModel provides the listed method or overload. A blank includes APIs that are missing and calls used only by the OpenStudio 3.11 branch, such as `WeatherFile.setWeatherFile`.
**Works As-Is?** is `Yes` when the observed use of the native call needs no shim or workaround. A blank means the call is not native, needs a workaround, or has not been verified without one. A native call used by another method's shim can still work as-is.
A shim is Ruby compatibility code in `resources/epmodel.rb` that keeps an existing call working using other EPModel APIs.
For example, `Surface#setAdjacentFoundation` writes the foundation pointer and boundary-condition field; the `InternalMassDefinition` façade maps calls onto `InteriorPartitionSurface`.
This is an observed-call list, not a complete EPModel API inventory. Ruby core methods and constructors' internal `initialize` calls are omitted.

| API Method Called | Native EPModel? | Works As-Is? | File location | Remaining Work / Current Handling |
| --- | --- | --- | --- | --- |
| `AdditionalProperties#getFeatureAsDouble` |  |  | `resources/epmodel.rb` | Process-local metadata adapter. |
| `AdditionalProperties#getFeatureAsInteger` |  |  | `resources/epmodel.rb` | Process-local metadata adapter. |
| `AdditionalProperties#getFeatureAsString` |  |  | `resources/epmodel.rb` | Process-local metadata adapter. |
| `AdditionalProperties#setFeature` |  |  | `resources/epmodel.rb` | Process-local, handle-keyed metadata; not serialized, and clone/merge isolation and handle remapping are not implemented. Reused handles can share metadata. |
| `AirTerminalSingleDuctUncontrolled.new(model, schedule)` |  |  | `resources/hvac.rb`, `resources/epmodel.rb` | Shim returns `AirTerminalSingleDuctVAVNoReheat` with minimum flow fraction and fixed minimum flow set to zero. This is a supported substitute, but may differ from the 3.11 uncontrolled terminal behavior. |
| `AirLoopHVAC#addBranchForZone(zone, terminal)` | Yes | Yes | `resources/epmodel.rb` | Native EPModel branch operation delegated to by the legacy-name shim. |
| `AirLoopHVAC#multiAddBranchForZone(zone, terminal)` |  |  | `resources/hvac.rb`, `resources/epmodel.rb` | Shim delegates to EPModel's `addBranchForZone(zone, terminal)`, matching the legacy overload's zone/terminal branch attachment. |
| `BoilerHotWater#plantLoop` | Yes |  | `resources/waterheater.rb`, `resources/epmodel.rb` | The EPModel optional is empty for the indirect-DHW boiler. EPModel resolves its plant loop by searching plant-loop supply components; OpenStudio 3.11 retains the native relationship. |
| `CoilCoolingDXMultiSpeed#addStage(stage)` |  |  | `resources/hvac.rb`, `resources/epmodel.rb` | Class-level shim writes the cooling stage fields to an extensible group and updates `Number of Speeds` once the second stage is added, as required by the IDD minimum. |
| `CoilCoolingDXMultiSpeed#stages` |  |  | `resources/hvac.rb`, `resources/epmodel.rb` | Class-level shim returns the cooling StageData façades recorded by `addStage`; this supports latent-degradation EMS and airflow checks. The list is process-local and is not reconstructed after model reload or clone. |
| `CoilCoolingDXMultiSpeedStageData.new(model, ...)` |  |  | `resources/hvac.rb`, `resources/epmodel.rb` | EPModel lacks the cooling StageData class; a compatibility class under the legacy namespace collects the existing setter calls for the `addStage` shim. |
| `CoilHeatingDXMultiSpeed#addStage(stage)` |  |  | `resources/hvac.rb`, `resources/epmodel.rb` | Class-level shim writes the heating stage fields to an extensible group and updates `Number of Speeds` once the second stage is added, as required by the IDD minimum. |
| `CoilHeatingDXMultiSpeed#stages` |  |  | `resources/hvac.rb`, `resources/epmodel.rb` | Class-level shim returns the heating StageData façades recorded by `addStage`; this supports backup staging and airflow checks. The list is process-local and is not reconstructed after model reload or clone. |
| `CoilHeatingDXMultiSpeedStageData.new(model, ...)` |  |  | `resources/hvac.rb`, `resources/epmodel.rb` | EPModel lacks the heating StageData class; a compatibility class under the legacy namespace collects the existing setter calls for the `addStage` shim. |
| `Construction#setLayers` | Yes | Yes | `resources/model.rb` | |
| `Construction#setName` | Yes | Yes | `resources/model.rb` | |
| `Construction.new(model)` | Yes | Yes | `resources/model.rb` | |
| `ConvergenceLimits#setMaximumHVACIterations` | Yes | Yes | `resources/simcontrols.rb` | |
| `ConvergenceLimits#setMinimumSystemTimestep` | Yes | Yes | `resources/simcontrols.rb` | |
| `ElectricEquipment#setEndUseSubcategory` | Yes | Yes | `resources/model.rb` | |
| `ElectricEquipment#setFractionLatent` | Yes | Yes | `resources/model.rb` | |
| `ElectricEquipment#setFractionLost` | Yes | Yes | `resources/model.rb` | |
| `ElectricEquipment#setFractionRadiant` | Yes | Yes | `resources/model.rb` | |
| `ElectricEquipment#setName` | Yes | Yes | `resources/model.rb` | |
| `ElectricEquipment#setSchedule(schedule)` |  |  | `resources/model.rb`, `resources/epmodel.rb` | Shim writes the `Schedule Name` object reference and supplies the legacy `Fractional` type limits when the schedule has none. |
| `ElectricEquipment#setSpace(space)` |  |  | `resources/model.rb`, `resources/epmodel.rb` | Shim writes the `Zone or ZoneList or Space or SpaceList Name` object reference. |
| `ElectricEquipment.new(definition)` |  |  | `resources/model.rb`, `resources/epmodel.rb` | Shim returns the underlying EPModel ElectricEquipment object held by the definition façade. |
| `ElectricEquipment.new(model)` | Yes | Yes | `resources/epmodel.rb` | Creates the object held by the ElectricEquipmentDefinition façade. |
| `ElectricEquipmentDefinition#setDesignLevel` |  |  | `resources/model.rb`, `resources/epmodel.rb` | Definition façade delegates the design level to the EPModel ElectricEquipment object. |
| `ElectricEquipmentDefinition#setFractionLatent` |  |  | `resources/model.rb`, `resources/epmodel.rb` | Definition façade delegates to the EPModel ElectricEquipment object. |
| `ElectricEquipmentDefinition#setFractionLost` |  |  | `resources/model.rb`, `resources/epmodel.rb` | Definition façade delegates to the EPModel ElectricEquipment object. |
| `ElectricEquipmentDefinition#setFractionRadiant` |  |  | `resources/model.rb`, `resources/epmodel.rb` | Definition façade delegates to the EPModel ElectricEquipment object. |
| `ElectricEquipmentDefinition#setName` |  |  | `resources/model.rb`, `resources/epmodel.rb` | Definition façade delegates to the EPModel ElectricEquipment object. |
| `ElectricEquipmentDefinition.new(model)` |  |  | `resources/model.rb`, `resources/epmodel.rb` | Creates the underlying EPModel ElectricEquipment object. |
| `ElectricLoadCenterDistribution#addGenerator(generator)` |  |  | `resources/generator.rb`, `resources/pv.rb`, `resources/epmodel.rb` | Shim attaches microturbines and PVWatts generators through an `ElectricLoadCenter:Generators` list and sets `Baseload` if no operation scheme was specified. |
| `ElectricLoadCenterDistribution#electricalStorage` |  |  | `resources/output.rb`, `resources/epmodel.rb` | Shim resolves the electrical storage pointer for meter creation. |
| `ElectricLoadCenterDistribution#generators` |  |  | `resources/output.rb`, `resources/epmodel.rb` | Shim reads generator pointers from the load center's generator list. |
| `ElectricLoadCenterDistribution#inverter` |  |  | `resources/output.rb`, `resources/epmodel.rb` | Shim resolves the inverter pointer for meter creation. |
| `ElectricLoadCenterDistribution#setElectricalStorage(storage)` |  |  | `resources/battery.rb`, `resources/epmodel.rb` | Shim writes the `Electrical Storage Object Name` pointer without changing the configured bus type or operating scheme. |
| `ElectricLoadCenterDistribution#setInverter(inverter)` |  |  | `resources/pv.rb`, `resources/epmodel.rb` | Shim writes the inverter pointer and sets `DirectCurrentWithInverter` if no bus type was specified. |
| `EnergyManagementSystemActuator.new(model_object, component_type, control_type)` | Yes | Yes | `resources/model.rb` | EPModel path uses the constructor without a SpaceLoadInstance cast; OpenStudio 3.11 retains its SpaceLoadInstance-specific overload. |
| `EnergyManagementSystemGlobalVariable#name` |  |  | `resources/airflow.rb`, `resources/epmodel.rb` | Shim returns the ERL variable name from the first extensible group; EPModel's inherited ModelObject name is empty. |
| `EnergyManagementSystemOutputVariable#setEMSProgramOrSubroutineName(program)` |  |  | `resources/model.rb` | Shim writes the `EMS Program or Subroutine Name` pointer; the EPModel wrapper does not expose the typed relationship setter. |
| `EnergyManagementSystemProgram#addLine(line)` |  |  | `resources/hvac.rb`, `resources/epmodel.rb` | Shim appends a `ProgramLine` group, removes CR/LF and commas from program text, and stores `!` comments as field comments. |
| `EnergyManagementSystemSensor#setKeyName` | Yes | Yes | `resources/model.rb` | |
| `EnergyManagementSystemSensor#setName` | Yes | Yes | `resources/model.rb` | |
| `EnergyManagementSystemSensor#setOutputVariableOrMeterName` | Yes | Yes | `resources/model.rb` | Used after construction as an overload workaround. |
| `EnergyManagementSystemSensor.new(model)` | Yes | Yes | `resources/model.rb` | Uses model-only constructor, then sets the output name because the two-argument overload is unavailable. |
| `EnergyManagementSystemSubroutine#addLine(line)` |  |  | `resources/airflow.rb`, `resources/epmodel.rb` | Shim appends a `ProgramLine` group, removes CR/LF and commas from program text, and stores `!` comments as field comments. |
| `FanSystemModel#numberofSpeeds` | Yes |  | `resources/epmodel.rb` | EPModel returns zero when `Number of Speeds` is blank; shim returns the legacy default of one and preserves explicit counts. |
| `FanSystemModel#outletModelObject` | Yes | Yes | `resources/hvac.rb` | EPModel latent-degradation EMS sensors use the actual fan outlet node name; OpenStudio 3.11 retains its translator-generated node name. |
| `FoundationKiva#addCustomBlock(material, depth, x, z)` |  |  | `resources/constructions.rb` | Implemented with extensible-group field writes in `epmodel.rb`. |
| `FoundationKiva#setExteriorHorizontalInsulationMaterial(material)` |  |  | `resources/constructions.rb`, `resources/epmodel.rb` | EPModel lacks the typed material setter; a class-level override writes the material pointer to the corresponding `Foundation:Kiva` field. |
| `FoundationKiva#setExteriorVerticalInsulationMaterial(material)` |  |  | `resources/constructions.rb`, `resources/epmodel.rb` | EPModel lacks the typed material setter; a class-level override writes the material pointer to the corresponding `Foundation:Kiva` field. |
| `FoundationKiva#setInteriorHorizontalInsulationMaterial(material)` |  |  | `resources/constructions.rb`, `resources/epmodel.rb` | EPModel lacks the typed material setter; a class-level override writes the material pointer to the corresponding `Foundation:Kiva` field. |
| `FoundationKiva#setInteriorVerticalInsulationMaterial(material)` |  |  | `resources/constructions.rb`, `resources/epmodel.rb` | EPModel lacks the typed material setter; a class-level override writes the material pointer to the corresponding `Foundation:Kiva` field. |
| `FoundationKiva#numExtensibleGroups` | Yes | Yes | `resources/epmodel.rb` | Used to enforce the ten-group limit. |
| `FoundationKiva#pushExtensibleGroup` | Yes | Yes | `resources/epmodel.rb` | Used by the `addCustomBlock` shim. |
| `FoundationKiva#setInitialIndoorAirTemperature` | Yes | Yes | `resources/constructions.rb` | |
| `FoundationKiva#setWallDepthBelowSlab` | Yes | Yes | `resources/constructions.rb` | |
| `FoundationKiva#setWallHeightAboveGrade` | Yes | Yes | `resources/constructions.rb` | |
| `FoundationKiva.new(model)` | Yes | Yes | `resources/constructions.rb` | |
| `FoundationKivaSettings#setDeepGroundBoundaryCondition` | Yes | Yes | `resources/constructions.rb` | |
| `FoundationKivaSettings#setDeepGroundDepth` | Yes | Yes | `resources/constructions.rb` | |
| `FoundationKivaSettings#setFarFieldWidth` | Yes | Yes | `resources/constructions.rb` | |
| `FoundationKivaSettings#setGroundSolarAbsorptivity` | Yes | Yes | `resources/constructions.rb` | |
| `FoundationKivaSettings#setGroundSurfaceRoughness` | Yes | Yes | `resources/constructions.rb` | |
| `FoundationKivaSettings#setGroundThermalAbsorptivity` | Yes | Yes | `resources/constructions.rb` | |
| `FoundationKivaSettings#setMaximumCellGrowthCoefficient` | Yes | Yes | `resources/constructions.rb` | |
| `FoundationKivaSettings#setMinimumCellDimension` | Yes | Yes | `resources/constructions.rb` | |
| `FoundationKivaSettings#setSimulationTimestep` | Yes | Yes | `resources/constructions.rb` | |
| `FoundationKivaSettings#setSoilConductivity` | Yes | Yes | `resources/constructions.rb` | |
| `FoundationKivaSettings#setSoilDensity` | Yes | Yes | `resources/constructions.rb` | |
| `FoundationKivaSettings#setSoilSpecificHeat` | Yes | Yes | `resources/constructions.rb` | |
| `GeneratorMicroTurbine#electricalEfficiencyFunctionofPartLoadRatioCurve` |  |  | `resources/generator.rb` | Only used to remove a legacy constructor default; EPModel creates no default curve. |
| `GeneratorMicroTurbine#electricalEfficiencyFunctionofTemperatureCurve` |  |  | `resources/generator.rb` | Only used to remove a legacy constructor default; EPModel creates no default curve. |
| `GeneratorMicroTurbine#electricalPowerFunctionofTemperatureandElevationCurve` |  |  | `resources/generator.rb` | Only used to remove a legacy constructor default; EPModel creates no default curve. |
| `GeneratorMicroTurbine#setElectricalEfficiencyFunctionofPartLoadRatioCurve(curve)` |  |  | `resources/generator.rb`, `resources/epmodel.rb` | Shim writes the typed curve reference through the IDD field. |
| `GeneratorMicroTurbine#setElectricalEfficiencyFunctionofTemperatureCurve(curve)` |  |  | `resources/generator.rb`, `resources/epmodel.rb` | Shim writes the typed curve reference through the IDD field. |
| `GeneratorPVWatts.new(model, capacity)` |  |  | `resources/pv.rb`, `resources/epmodel.rb` | Shim calls the native model-only constructor and sets DC system capacity. |
| `GeneratorMicroTurbine#setElectricalPowerFunctionofTemperatureandElevationCurve(curve)` |  |  | `resources/generator.rb`, `resources/epmodel.rb` | Shim writes the typed curve reference through the IDD field. |
| `GroundHeatExchangerVertical#addGFunction(lnValue, gValue)` | Yes | Yes | `resources/hvac.rb` | |
| `GroundHeatExchangerVertical#boreHoleLength` | Yes | Yes | `resources/hvac.rb` | |
| `GroundHeatExchangerVertical#boreHoleRadius` | Yes | Yes | `resources/hvac.rb` | |
| `GroundHeatExchangerVertical#designFlowRate` | Yes | Yes | `resources/hvac.rb` | |
| `GroundHeatExchangerVertical#gFunctionReferenceRatio` | Yes | Yes | `resources/hvac.rb` | |
| `GroundHeatExchangerVertical#gFunctions` | Yes | Yes | `resources/hvac.rb` | |
| `GroundHeatExchangerVertical#groundThermalConductivity` | Yes | Yes | `resources/hvac.rb` | |
| `GroundHeatExchangerVertical#groundThermalHeatCapacity` | Yes | Yes | `resources/hvac.rb` | |
| `GroundHeatExchangerVertical#groundTemperature` |  |  | `resources/hvac.rb`, `resources/epmodel.rb` | Shim delegates to `undisturbedGroundTemperatureModel().averageSoilSurfaceTemperature`. No direct EnergyPlus field; temperature is managed by undisturbed ground model. |
| `GroundHeatExchangerVertical#maximumLengthofSimulation` |  |  | `resources/hvac.rb`, `resources/epmodel.rb` | Shim returns default OptionalInt(1). No direct EnergyPlus field; this is a known EPModel limitation. |
| `GroundHeatExchangerVertical#numberofBoreHoles` | Yes | Yes | `resources/hvac.rb` | |
| `GroundHeatExchangerVertical#removeAllGFunctions` | Yes | Yes | `resources/hvac.rb` | |
| `GroundHeatExchangerVertical#setBoreHoleLength(value)` | Yes | Yes | `resources/hvac.rb` | |
| `GroundHeatExchangerVertical#setBoreHoleRadius(value)` | Yes | Yes | `resources/hvac.rb` | |
| `GroundHeatExchangerVertical#setDesignFlowRate(value)` | Yes | Yes | `resources/hvac.rb` | |
| `GroundHeatExchangerVertical#setGFunctionReferenceRatio(value)` | Yes | Yes | `resources/hvac.rb` | |
| `GroundHeatExchangerVertical#setGroundThermalConductivity(value)` | Yes | Yes | `resources/hvac.rb` | |
| `GroundHeatExchangerVertical#setGroundThermalHeatCapacity(value)` | Yes | Yes | `resources/hvac.rb` | |
| `GroundHeatExchangerVertical#setGroundTemperature(temperature)` |  |  | `resources/hvac.rb`, `resources/epmodel.rb` | Shim delegates to `undisturbedGroundTemperatureModel().setAverageSoilSurfaceTemperature()`. No direct EnergyPlus field; temperature is managed by undisturbed ground model. |
| `GroundHeatExchangerVertical#setGroutThermalConductivity(value)` | Yes | Yes | `resources/hvac.rb` | |
| `GroundHeatExchangerVertical.new(model, ground_temperature_model)` | Yes |  | `resources/hvac.rb`, `resources/epmodel.rb` | Constructor shim fills the associated vertical properties object's grout and pipe thermal heat capacities using the legacy ForwardTranslator defaults of 3.90E+06 and 1.77E+06 J/m3-K. EPModel does not currently initialize these required EnergyPlus fields. |
| `GroundHeatExchangerVertical#setMaximumLengthofSimulation(value)` |  |  | `resources/hvac.rb`, `resources/epmodel.rb` | Shim silently succeeds (returns true). No direct EnergyPlus field; this is a known EPModel limitation. |
| `GroundHeatExchangerVertical#setNumberofBoreHoles(value)` | Yes | Yes | `resources/hvac.rb` | |
| `GroundHeatExchangerVertical#setPipeOutDiameter(value)` | Yes | Yes | `resources/hvac.rb` | |
| `GroundHeatExchangerVertical#setPipeThermalConductivity(value)` | Yes | Yes | `resources/hvac.rb` | |
| `GroundHeatExchangerVertical#setPipeThickness(value)` | Yes | Yes | `resources/hvac.rb` | |
| `GroundHeatExchangerVertical#setUTubeDistance(value)` | Yes | Yes | `resources/hvac.rb` | |
| `GroundHeatExchangerVertical#undisturbedGroundTemperatureModel` | Yes | Yes | `resources/hvac.rb` | |
| `InsideSurfaceConvectionAlgorithm#setAlgorithm` | Yes | Yes | `resources/simcontrols.rb` | |
| `IdfObject#clone(keepHandle)` | Yes | Yes | `resources/epmodel.rb` | Clones a model object's backing IDF object before adding the copy to the model for the indirect-DHW loop rebuild. |
| `InteriorPartitionSurface#setConstruction` | Yes | Yes | `resources/epmodel.rb` | |
| `InteriorPartitionSurface#setName` | Yes | Yes | `resources/epmodel.rb` | |
| `InteriorPartitionSurface#setPointer` | Yes | Yes | `resources/epmodel.rb` | Sets the Space reference. |
| `InteriorPartitionSurface#setSurfaceArea` | Yes | Yes | `resources/epmodel.rb` | |
| `InteriorPartitionSurface.new(vertices, model)` | Yes | Yes | `resources/epmodel.rb` | Underlying object for the InternalMass compatibility façade. |
| `InternalMass#internalMassDefinition` |  |  | `resources/constructions.rb` | Returns the façade used for construction assignment. |
| `InternalMass#setName` |  |  | `resources/model.rb` | Compatibility façade. |
| `InternalMass#setSpace` |  |  | `resources/model.rb` | Compatibility façade. |
| `InternalMass.new(definition)` |  |  | `resources/model.rb` | Compatibility façade over `InteriorPartitionSurface`. |
| `InternalMassDefinition#adjacentSurface` |  |  | `resources/constructions.rb` | Returns an empty optional; EPModel internal masses have no adjacent surface. |
| `InternalMassDefinition#setConstruction` |  |  | `resources/constructions.rb` | Delegates to `InteriorPartitionSurface#setConstruction`. |
| `InternalMassDefinition#setName` |  |  | `resources/model.rb` | Delegates to `InteriorPartitionSurface#setName`. |
| `InternalMassDefinition#setSpace` |  |  | `resources/model.rb` | Writes the EnergyPlus Space reference. |
| `InternalMassDefinition#setSurfaceArea` |  |  | `resources/model.rb` | Delegates to `InteriorPartitionSurface#setSurfaceArea`. |
| `InternalMassDefinition.new(model)` |  |  | `resources/model.rb` | Creates an `InteriorPartitionSurface` with placeholder vertices, then sets its explicit area. |
| `MeterCustom#addKeyVarGroup(key, output_variable_or_meter)` |  |  | `resources/model.rb`, `resources/epmodel.rb` | Shim appends a group with `Key Name` and `Output Variable or Meter Name` fields. |
| `MeterCustomDecrement#addKeyVarGroup(key, output_variable_or_meter)` |  |  | `resources/model.rb`, `resources/epmodel.rb` | Shares the extensible-group shim used by `MeterCustom`. |
| `Model#alwaysOffDiscreteSchedule` |  |  | `resources/hvac.rb`, `resources/meta_measure.rb`, `resources/epmodel.rb` | Shim creates or reuses a zero-valued constant schedule with discrete type limits. EPModel removes unreferenced `Schedule:Constant` objects from the translated workspace while preserving schedule names referenced by EMS sensors and actuators. |
| `Model#getBoilerHotWaters` | Yes |  | `resources/waterheater.rb`, `resources/epmodel.rb` | EPModel's typed collection getter evaluates unset baseboard-coil sizing fields and triggers native assertions. A class-level override filters model objects by IDD type before casting, preserving the shared resource call. |
| `Model#addObject(idf_object)` | Yes | Yes | `resources/epmodel.rb` | Adds the cloned boiler and pump IDF objects used by the indirect-DHW loop rebuild. |
| `Model#getConvergenceLimits` | Yes | Yes | `resources/simcontrols.rb` | |
| `Model#getElectricLoadCenterDistributions` | Yes |  | `resources/output.rb`, `resources/epmodel.rb` | Native collection getter crashes on the generator sample; the override finds load centers by IDD type before casting. |
| `Model#getFoundationKivas` | Yes | Yes | `resources/epmodel.rb` | Resolves the typed target for `adjacentFoundation`. |
| `Model#getFoundationKivaSettings` | Yes | Yes | `resources/constructions.rb` | |
| `Model#getInsideSurfaceConvectionAlgorithm` | Yes | Yes | `resources/simcontrols.rb` | |
| `Model#getObjectsByType` | Yes | Yes | `resources/epmodel.rb` | Enumerates generic shading IDD objects for the shading-group shim. |
| `Model#getOutsideSurfaceConvectionAlgorithm` | Yes | Yes | `resources/simcontrols.rb` | |
| `Model#getModelObjects` |  |  | `resources/output.rb`, `resources/epmodel.rb` | Shim delegates to EPModel's `Model#objects`, which returns an Array. |
| `Model#getRunPeriod` | Yes | Yes | `resources/location.rb`, `resources/schedules.rb`, `resources/simcontrols.rb` | |
| `Model#getRunPeriodControlDaylightSavingTime` | Yes | Yes | `resources/location.rb` | |
| `Model#getScheduleTypeLimitss` | Yes | Yes | `resources/model.rb` | |
| `Model#getShadingSurfaceGroups` |  |  | `resources/geometry.rb`, `resources/epmodel.rb` | Shim wraps generic `OS_ShadingSurfaceGroup` objects in compatibility facades. |
| `Model#getShadowCalculation` | Yes | Yes | `resources/simcontrols.rb` | |
| `Model#getSimpleGlazings` | Yes | Yes | `resources/model.rb` | |
| `Model#getSimulationControl` | Yes | Yes | `resources/simcontrols.rb` | |
| `Model#getSite` | Yes | Yes | `resources/location.rb` | |
| `Model#getSiteGroundTemperatureShallow` | Yes | Yes | `resources/location.rb` | |
| `Model#getStandardOpaqueMaterials` | Yes | Yes | `resources/model.rb` | |
| `Model#getSurfacePropertyExposedFoundationPerimeters` | Yes | Yes | `resources/epmodel.rb` | Checks for an existing property before creating one. |
| `Model#getSurfaces` | Yes | Yes | `resources/geometry.rb` | |
| `Model#getTimestep` | Yes | Yes | `resources/simcontrols.rb` | |
| `Model#toIdfFile` | Yes | Yes | `resources/epmodel.rb`, `resources/meta_measure.rb` | Used for direct EPModel export because the legacy ForwardTranslator accepts only OpenStudio Model. See [Direct IDF Export Normalization](#direct-idf-export-normalization). |
| `Model#workflowJSON` |  |  | `resources/model.rb` | Missing EPModel API; `add_schedule_file` uses `workflowJSON.filePaths` and `addFilePath` to register schedule-file directories. |
| `Model#getYearDescription` |  |  | `resources/location.rb`, `resources/schedules.rb` | Called only when `Version::UseEPModel` is false; EPModel reads/writes year fields through `RunPeriod`. |
| `Model#getZoneCapacitanceMultiplierResearchSpecial` | Yes | Yes | `resources/simcontrols.rb` | |
| `Model#objects` | Yes | Yes | `resources/model.rb`, `resources/meta_measure.rb` | |
| `Model.new` | Yes | Yes | `resources/meta_measure.rb` | |
| `ModelObject#additionalProperties` |  |  | `resources/epmodel.rb` | Returns the process-local compatibility adapter. |
| `ModelObject#getTarget` | Yes | Yes | `resources/epmodel.rb` | Resolves object references in association shims. |
| `ModelObject#iddObject` | Yes | Yes | `resources/epmodel.rb`, `resources/location.rb`, `resources/schedules.rb` | Used for generic RunPeriod field access and shim field lookup. |
| `ModelObject#setPointer` | Yes | Yes | `resources/epmodel.rb` | Used by relationship shims. |
| `ModelObject#to_AdditionalProperties` |  |  | `resources/output.rb`, `resources/meta_measure.rb`, `ReportSimulationOutput/measure.rb` | Cast is used only on the OpenStudio 3.11 path; EPModel uses a process-local `additionalProperties` adapter instead of model objects. |
| `ModelObject#to_SpaceLoadInstance` |  |  | `resources/model.rb` | Used only by the OpenStudio 3.11 actuator path; EPModel exposes no SpaceLoadInstance type or cast. |
| `Node#setpointManagers` | Yes |  | `resources/waterheater.rb`, `resources/epmodel.rb` | EPModel returns a vector that is not iterable from Ruby; the EPModel resource branch finds scheduled setpoint managers by their target node. The helper is intentionally narrower than the general getter, so a class-level override would change its semantics. |
| `PlantLoop#clone(model)` |  |  | `resources/waterheater.rb`, `resources/epmodel.rb` | EPModel's `Loop::clone` currently returns an empty Catchall object. The indirect-DHW path rebuilds a dedicated boiler loop in the EPModel compatibility layer by copying loop/sizing settings and recreating boiler-side components; general loop cloning remains an SDK gap. |
| `PlantLoop#setGlycolConcentration` | Yes |  | `resources/model.rb`, `resources/epmodel.rb` | EPModel's native implementation does not successfully preserve the legacy concentration on the EnergyPlus PlantLoop. The EPModel path instead uses `setGlycolFluidType` to create glycol property objects and set `UserDefinedFluidType`, preserving the requested concentration. |
| `PlantLoop#setGlycolFluidType(glycol_type, concentration)` |  |  | `resources/model.rb`, `resources/epmodel.rb` | Compatibility helper creates `FluidProperties:GlycolConcentration` and `FluidProperties:Name` and links the PlantLoop to them. The 3.11 path retains its native fluid type and concentration setters. |
| `OptionalFoundationKiva#get` | Yes | Yes | `resources/geometry.rb` | |
| `OptionalSchedule#get` | Yes | Yes | `resources/constructions.rb` | |
| `OptionalScheduleRuleset#get` | Yes | Yes | `resources/constructions.rb` | |
| `OptionalScheduleRuleset#is_initialized` | Yes | Yes | `resources/constructions.rb` | |
| `OptionalSurface#get` | Yes | Yes | `resources/geometry.rb` | |
| `OptionalSurface#is_initialized` | Yes | Yes | `resources/constructions.rb` | |
| `OptionalSurface.new` | Yes | Yes | `resources/epmodel.rb` | Empty optional returned by the InternalMass compatibility façade. |
| `OptionalSurfacePropertyExposedFoundationPerimeter.new` | Yes | Yes | `resources/epmodel.rb` | Wraps the exposed-perimeter object returned by the Surface shim. |
| `OptionalThermalZone#get` | Yes | Yes | `resources/geometry.rb`, `resources/hvac.rb` | |
| `OptionalThermostatSetpointDualSetpoint#get` | Yes | Yes | `resources/constructions.rb` | |
| `OptionalThermostatSetpointDualSetpoint#is_initialized` | Yes | Yes | `resources/constructions.rb` | |
| `OtherEquipment#setEndUseSubcategory` | Yes | Yes | `resources/model.rb` | |
| `OtherEquipment#setFuelType` | Yes | Yes | `resources/model.rb` | |
| `OtherEquipment#setName` | Yes | Yes | `resources/model.rb` | |
| `OtherEquipment#setSchedule(schedule)` |  |  | `resources/model.rb`, `resources/epmodel.rb` | Shim writes the `Schedule Name` object reference. |
| `OtherEquipment#setSpace(space)` |  |  | `resources/model.rb`, `resources/epmodel.rb` | Shim writes the `Zone or ZoneList or Space or SpaceList Name` object reference. |
| `OtherEquipment.new(definition)` |  |  | `resources/model.rb`, `resources/epmodel.rb` | Shim returns the underlying EPModel OtherEquipment object held by the definition façade. |
| `OtherEquipmentDefinition#setDesignLevel` |  |  | `resources/model.rb`, `resources/epmodel.rb` | Definition façade delegates the design level to the EPModel OtherEquipment object. |
| `OtherEquipmentDefinition#setFractionLatent` |  |  | `resources/model.rb`, `resources/epmodel.rb` | Definition façade delegates to the EPModel OtherEquipment object. |
| `OtherEquipmentDefinition#setFractionLost` |  |  | `resources/model.rb`, `resources/epmodel.rb` | Definition façade delegates to the EPModel OtherEquipment object. |
| `OtherEquipmentDefinition#setFractionRadiant` |  |  | `resources/model.rb`, `resources/epmodel.rb` | Definition façade delegates to the EPModel OtherEquipment object. |
| `OtherEquipmentDefinition#setName` |  |  | `resources/model.rb`, `resources/epmodel.rb` | Definition façade delegates to the EPModel OtherEquipment object. |
| `OtherEquipmentDefinition.new(model)` |  |  | `resources/model.rb`, `resources/epmodel.rb` | Creates the underlying EPModel OtherEquipment object. |
| `Model#getOtherEquipments` | Yes | Yes | `resources/hvac.rb` | Counts existing equipment for unique names. |
| `OutsideSurfaceConvectionAlgorithm#setAlgorithm` | Yes | Yes | `resources/simcontrols.rb` | |
| `People#setActivityLevelSchedule(schedule)` |  |  | `resources/internal_gains.rb`, `resources/epmodel.rb` | Shim writes the activity schedule pointer and supplies the legacy `ActivityLevel` type limits when the schedule has none. |
| `RunPeriod#getInt` | Yes | Yes | `resources/schedules.rb` | Generic field-index read of Begin Year. |
| `RunPeriod#iddObject` | Yes | Yes | `resources/location.rb`, `resources/schedules.rb` | Retrieves field indices for generic RunPeriod field access. |
| `RunPeriod#setBeginDayOfMonth` | Yes | Yes | `resources/simcontrols.rb` | |
| `RunPeriod#setBeginMonth` | Yes | Yes | `resources/simcontrols.rb` | |
| `RunPeriod#setEndDayOfMonth` | Yes | Yes | `resources/simcontrols.rb` | |
| `RunPeriod#setEndMonth` | Yes | Yes | `resources/simcontrols.rb` | |
| `RunPeriod#setInt` | Yes | Yes | `resources/location.rb` | Generic field-index writes for Begin/End Year. |
| `RunPeriod#setString` | Yes | Yes | `resources/location.rb` | Generic field-index write for Day of Week for Start Day. |
| `RunPeriodControlDaylightSavingTime#setEndDate` | Yes | Yes | `resources/location.rb` | |
| `RunPeriodControlDaylightSavingTime#setStartDate` | Yes | Yes | `resources/location.rb` | |
| `Schedule#to_ScheduleInterval` |  |  | `resources/schedules.rb` | Used only when `Version::UseEPModel` is false; EPModel exposes no `ScheduleInterval` type. |
| `Schedule#to_ScheduleRuleset` | Yes | Yes | `resources/constructions.rb` | |
| `ScheduleConstant#setName` | Yes | Yes | `resources/model.rb` | |
| `ScheduleConstant#setScheduleTypeLimits` | Yes | Yes | `resources/model.rb` | |
| `ScheduleConstant#setValue` | Yes | Yes | `resources/model.rb` | |
| `ScheduleConstant.new(model)` | Yes | Yes | `resources/model.rb` | |
| `ScheduleDay#addValue` | Yes | Yes | `resources/model.rb` | |
| `ScheduleDay#setName` | Yes | Yes | `resources/model.rb` | |
| `ScheduleDay#values` | Yes | Yes | `resources/constructions.rb` | |
| `ScheduleRule#daySchedule` | Yes | Yes | `resources/model.rb` | |
| `ScheduleRule#setApplyFriday` | Yes | Yes | `resources/model.rb` | |
| `ScheduleRule#setApplyMonday` | Yes | Yes | `resources/model.rb` | |
| `ScheduleRule#setApplySaturday` | Yes | Yes | `resources/model.rb` | |
| `ScheduleRule#setApplySunday` | Yes | Yes | `resources/model.rb` | |
| `ScheduleRule#setApplyThursday` | Yes | Yes | `resources/model.rb` | |
| `ScheduleRule#setApplyTuesday` | Yes | Yes | `resources/model.rb` | |
| `ScheduleRule#setApplyWednesday` | Yes | Yes | `resources/model.rb` | |
| `ScheduleRule#setEndDate` | Yes | Yes | `resources/model.rb`, `resources/schedules.rb` | |
| `ScheduleRule#setName` | Yes | Yes | `resources/model.rb` | |
| `ScheduleRule#setStartDate` | Yes | Yes | `resources/model.rb` | |
| `ScheduleRule.new(schedule)` | Yes |  | `resources/model.rb`, `resources/epmodel.rb` | Constructor shim assigns the ruleset's type limits to its day schedule when limits exist. |
| `ScheduleRuleset#defaultDaySchedule` | Yes | Yes | `resources/model.rb` | |
| `ScheduleRuleset#getDaySchedule(date)` | Yes | Yes | `resources/constructions.rb` | EPModel provides a single-date getter; OpenStudio 3.11 uses a date-range getter returning a collection. The resource branch keeps the API shapes explicit instead of adding a partial range-method override. |
| `ScheduleRuleset#name` | Yes | Yes | `resources/model.rb` | |
| `ScheduleRuleset#setName` | Yes | Yes | `resources/model.rb` | |
| `ScheduleRuleset#setScheduleTypeLimits` | Yes |  | `resources/model.rb`, `resources/epmodel.rb` | Shim propagates type limits to the default, special, and rule day schedules; native EPModel only updates the ruleset. |
| `ScheduleRuleset.new(model)` | Yes | Yes | `resources/model.rb` | |
| `ScheduleTypeLimits#name` | Yes | Yes | `resources/model.rb` | |
| `ScheduleTypeLimits#setLowerLimitValue` | Yes | Yes | `resources/model.rb` | |
| `ScheduleTypeLimits#setName` | Yes | Yes | `resources/model.rb` | |
| `ScheduleTypeLimits#setNumericType` | Yes | Yes | `resources/model.rb` | |
| `ScheduleTypeLimits#setUpperLimitValue` | Yes | Yes | `resources/model.rb` | |
| `ScheduleTypeLimits.new(model)` | Yes | Yes | `resources/model.rb` | |
| `SetpointManagerScheduled#setSchedule(schedule)` | Yes | Yes | `resources/epmodel.rb` | Constructor compatibility shim assigns the schedule after creating the model-only object. |
| `SetpointManagerFollowGroundTemperature#addToNode(node)` | Yes |  | `resources/hvac.rb`, `resources/epmodel.rb` | EPModel's native method rejects the plant supply outlet node; the shim first tries the native method, then assigns that node directly for this specific case. |
| `SetpointManagerScheduled.new(model, schedule)` |  |  | `resources/waterheater.rb`, `resources/hvac.rb`, `resources/epmodel.rb` | EPModel constructor shim creates the manager with `model`, then calls `setSchedule(schedule)`; OpenStudio 3.11 uses the native overload. |
| `ShadingSurface#additionalProperties` |  |  | `resources/geometry.rb`, `resources/epmodel.rb` | Shim reads neighbor azimuth and distance from process-local metadata. |
| `ShadingSurface#setVertices(vertices)` |  |  | `resources/geometry.rb`, `resources/epmodel.rb` | Shim rewrites vertex extensible groups after transformation. |
| `ShadingSurface#vertices` |  |  | `resources/geometry.rb`, `resources/epmodel.rb` | Shim reads vertex extensible groups. |
| `ShadingSurface.new(vertices, model)` |  |  | `resources/geometry.rb`, `resources/waterheater.rb` | EPModel lacks `ShadingSurface`; neighbor shading cannot be created. |
| `ShadingSurfaceGroup#name` |  |  | `resources/geometry.rb`, `resources/epmodel.rb` | Shim returns the generic group's name string. |
| `ShadingSurfaceGroup#shadingSurfaces` |  |  | `resources/geometry.rb`, `resources/epmodel.rb` | Shim resolves surfaces whose group-name pointer matches this group. |
| `ShadowCalculation#setMaximumFiguresInShadowOverlapCalculations` | Yes | Yes | `resources/simcontrols.rb` | |
| `ShadowCalculation#setShadingCalculationUpdateFrequency` | Yes | Yes | `resources/simcontrols.rb` | |
| `SimpleGlazing#name` | Yes | Yes | `resources/model.rb` | |
| `SimpleGlazing#setName` | Yes | Yes | `resources/model.rb` | |
| `SimpleGlazing#setSolarHeatGainCoefficient` | Yes | Yes | `resources/model.rb` | |
| `SimpleGlazing#setUFactor` | Yes | Yes | `resources/model.rb` | |
| `SimpleGlazing#solarHeatGainCoefficient` | Yes | Yes | `resources/model.rb` | |
| `SimpleGlazing#uFactor` | Yes | Yes | `resources/model.rb` | |
| `SimpleGlazing.new(model)` | Yes | Yes | `resources/model.rb` | |
| `SimulationControl#setRunSimulationforSizingPeriods` | Yes | Yes | `resources/simcontrols.rb` | |
| `Site#setElevation` | Yes | Yes | `resources/location.rb` | |
| `Site#setKeepSiteLocationInformation` | Yes | Yes | `resources/location.rb` | |
| `Site#setLatitude` | Yes | Yes | `resources/location.rb` | |
| `Site#setLongitude` | Yes | Yes | `resources/location.rb` | |
| `Site#setName` | Yes | Yes | `resources/location.rb` | |
| `Site#setTimeZone` | Yes | Yes | `resources/location.rb` | |
| `SiteGroundTemperatureShallow#resetAllMonths` |  |  | `resources/location.rb` | Compatibility helper delegates to native monthly reset methods. |
| `SiteGroundTemperatureShallow#setAllMonthlyTemperatures` |  |  | `resources/location.rb` | Compatibility helper delegates to native monthly setters. |
| `Space#floorArea` | Yes | Yes | `resources/constructions.rb` | |
| `Space#name` | Yes | Yes | `resources/constructions.rb` | |
| `Space#setName` | Yes | Yes | `resources/geometry.rb` | |
| `Space#setThermalZone` | Yes | Yes | `resources/geometry.rb` | |
| `Space#setVolume` | Yes | Yes | `resources/geometry.rb` | |
| `Space#thermalZone` | Yes | Yes | `resources/constructions.rb`, `resources/geometry.rb`, `resources/hvac.rb` | |
| `Space.new(model)` | Yes | Yes | `resources/geometry.rb` | |
| `SpaceInfiltrationEffectiveLeakageArea#setSchedule(schedule)` |  |  | `resources/model.rb`, `resources/epmodel.rb` | Class-level shim writes the `Schedule Name` pointer. |
| `SpaceInfiltrationEffectiveLeakageArea#setSpace(space)` |  |  | `resources/model.rb`, `resources/epmodel.rb` | Class-level shim writes the space pointer to the `Zone or Space Name` field. |
| `SpaceInfiltrationEffectiveLeakageArea.new(model)` | Yes | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#conductivity` | Yes | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#density` | Yes | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#name` | Yes | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#roughness` | Yes | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#setConductivity` | Yes | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#setDensity` | Yes | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#setName` | Yes | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#setRoughness` | Yes | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#setSolarAbsorptance` | Yes | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#setSpecificHeat` | Yes | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#setThermalAbsorptance` | Yes | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#setThickness` | Yes | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#setVisibleAbsorptance` | Yes | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#solarAbsorptance` | Yes | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#specificHeat` | Yes | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#thermalAbsorptance` | Yes | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial#thickness` | Yes | Yes | `resources/model.rb` | |
| `StandardOpaqueMaterial.new(model)` | Yes | Yes | `resources/model.rb` | |
| `SubSurface#setConstruction` | Yes | Yes | `resources/constructions.rb` | |
| `SubSurface#setName` | Yes | Yes | `resources/geometry.rb` | |
| `SubSurface#setSubSurfaceType` | Yes | Yes | `resources/geometry.rb` | |
| `SubSurface#setSurface` | Yes | Yes | `resources/geometry.rb` | |
| `SubSurface#shadingSurfaceGroups` |  |  | `resources/geometry.rb`, `resources/epmodel.rb` | Shim finds groups whose shaded-object pointer matches this subsurface. |
| `SubSurface#subSurfaceType` | Yes | Yes | `resources/epmodel.rb` | Validates allowed types in the incident-solar multiplier constructor shim. |
| `SubSurface.new(vertices, model)` | Yes | Yes | `resources/geometry.rb` | |
| `SubSurfaceVector#to_ary` |  |  | `resources/epmodel.rb` | Converts the native vector to an Array for existing `Array#+` use in `geometry.rb`. |
| `Surface#<=>` | Yes | Yes | `resources/geometry.rb` | |
| `Surface#adjacentFoundation` |  |  | `resources/geometry.rb`, `resources/epmodel.rb` | Shim resolves the stored Kiva handle to a typed optional. |
| `Surface#adjacentSurface` | Yes | Yes | `resources/constructions.rb` | |
| `Surface#createAdjacentSurface` | Yes | Yes | `resources/geometry.rb` | |
| `Surface#createSurfacePropertyExposedFoundationPerimeter` |  |  | `resources/constructions.rb` | Shim creates and links the property through `Surface Name`. |
| `Surface#outsideBoundaryCondition` | Yes | Yes | `resources/geometry.rb` | |
| `Surface#setAdjacentFoundation(foundation)` |  |  | `resources/constructions.rb` | Shim sets the Kiva pointer and `OutsideBoundaryCondition`. |
| `Surface#setConstruction` | Yes | Yes | `resources/constructions.rb` | |
| `Surface#setName` | Yes | Yes | `resources/geometry.rb` | |
| `Surface#setOutsideBoundaryCondition` | Yes | Yes | `resources/geometry.rb`, `resources/epmodel.rb` | |
| `Surface#setSpace` | Yes | Yes | `resources/geometry.rb` | |
| `Surface#setSurfacePropertyOtherSideCoefficients(other_side_coefficients)` |  |  | `resources/geometry.rb`, `resources/epmodel.rb` | Class-level shim sets the `Outside Boundary Condition Object` pointer and the `OtherSideCoefficients` boundary condition. |
| `Surface#setSunExposure` | Yes | Yes | `resources/geometry.rb` | |
| `Surface#setSurfaceType` | Yes | Yes | `resources/geometry.rb` | |
| `Surface#setWindExposure` | Yes | Yes | `resources/geometry.rb` | |
| `Surface#surfaceType` | Yes | Yes | `resources/geometry.rb` | |
| `Surface#tilt` | Yes | Yes | `resources/constructions.rb` | |
| `Surface.new(vertices, model)` | Yes | Yes | `resources/geometry.rb` | |
| `SurfacePropertyExposedFoundationPerimeter#setExposedPerimeterCalculationMethod` | Yes | Yes | `resources/epmodel.rb` | |
| `SurfacePropertyExposedFoundationPerimeter#setTotalExposedPerimeter` | Yes | Yes | `resources/epmodel.rb` | |
| `SurfacePropertyExposedFoundationPerimeter.new(model)` | Yes | Yes | `resources/epmodel.rb` | Native object constructor used by the Surface shim. |
| `SurfacePropertyIncidentSolarMultiplier#setIncidentSolarMultiplier` | Yes | Yes | `resources/epmodel.rb` | Sets the legacy constructor's default value of 1.0. |
| `SurfacePropertyIncidentSolarMultiplier#setIncidentSolarMultiplierSchedule` |  |  | `resources/constructions.rb`, `resources/epmodel.rb` | Compatibility shim writes the schedule reference. |
| `SurfacePropertyIncidentSolarMultiplier#setSubSurface` |  |  | `resources/epmodel.rb` | Compatibility shim writes the subsurface reference. |
| `SurfacePropertyIncidentSolarMultiplier.new(model)` | Yes | Yes | `resources/epmodel.rb` | Native constructor used by the subsurface overload. |
| `SurfacePropertyIncidentSolarMultiplier.new(subsurface)` |  |  | `resources/constructions.rb` | Constructor overload supplied by the compatibility shim. |
| `SurfacePropertyOtherSideCoefficients#setConstantTemperatureSchedule(schedule)` |  |  | `resources/geometry.rb`, `resources/epmodel.rb` | Class-level shim writes the `Constant Temperature Schedule Name` pointer. |
| `SurfacePropertyOtherSideCoefficients.new(model)` | Yes | Yes | `resources/geometry.rb` | |
| `ThermalZone#name` | Yes | Yes | `resources/hvac.rb` | |
| `ThermalZone#setMultiplier` | Yes | Yes | `resources/geometry.rb` | |
| `ThermalZone#setName` | Yes | Yes | `resources/geometry.rb` | |
| `ThermalZone#spaces` |  |  | `resources/hvac.rb`, `resources/epmodel.rb` | Shim filters `Model#getSpaces` by the Space's typed ThermalZone reference. |
| `ThermalZone#floorArea` |  |  | `ReportSimulationOutput/measure.rb`, `resources/epmodel.rb` | Shim sums the `floorArea` of spaces assigned to the zone, matching the legacy ThermalZone API. |
| `ThermalZone#isPlenum` |  |  | `resources/output.rb`, `resources/epmodel.rb` | Shim checks return and supply plenum objects for a matching ThermalZone reference. |
| `ThermalZone#setSequentialCoolingFractionSchedule(equipment, schedule)` |  |  | `resources/hvac.rb`, `resources/epmodel.rb` | Shim resolves the zone's `ZoneHVACEquipmentConnections` and delegates to its native equipment-list setter. |
| `ThermalZone#setSequentialHeatingFractionSchedule(equipment, schedule)` |  |  | `resources/hvac.rb`, `resources/epmodel.rb` | Shim resolves the zone's `ZoneHVACEquipmentConnections` and delegates to its native equipment-list setter. |
| `ThermalZone#setThermostatSetpointDualSetpoint` | Yes | Yes | `resources/hvac.rb` | |
| `ThermalZone#setVolume` | Yes | Yes | `resources/geometry.rb` | |
| `ThermalZone#thermostatSetpointDualSetpoint` | Yes | Yes | `resources/constructions.rb` | |
| `ThermalZone.new(model)` | Yes | Yes | `resources/geometry.rb` | |
| `ThermostatSetpointDualSetpoint#coolingSetpointTemperatureSchedule` | Yes | Yes | `resources/constructions.rb` | |
| `ThermostatSetpointDualSetpoint#heatingSetpointTemperatureSchedule` | Yes | Yes | `resources/constructions.rb` | |
| `ThermostatSetpointDualSetpoint#setCoolingSetpointTemperatureSchedule` | Yes |  | `resources/hvac.rb`, `resources/epmodel.rb` | Shim propagates type limits inferred by the native thermostat setter to the ruleset's day schedules. |
| `ThermostatSetpointDualSetpoint#setHeatingSetpointTemperatureSchedule` | Yes |  | `resources/hvac.rb`, `resources/epmodel.rb` | Shim propagates type limits inferred by the native thermostat setter to the ruleset's day schedules. |
| `ThermostatSetpointDualSetpoint#setName` | Yes | Yes | `resources/hvac.rb` | |
| `ThermostatSetpointDualSetpoint#setTemperatureDifferenceBetweenCutoutAndSetpoint` | Yes | Yes | `resources/hvac.rb` | |
| `ThermostatSetpointDualSetpoint.new(model)` | Yes | Yes | `resources/hvac.rb` | |
| `Timestep#setNumberOfTimestepsPerHour` | Yes | Yes | `resources/simcontrols.rb` | |
| `SupplyAirflowRatioField.new(heating_ratio, cooling_ratio)` |  |  | `resources/hvac.rb`, `resources/epmodel.rb` | Compatibility façade stores the optional heating and cooling ratios for the unitary performance shim. |
| `SupplyAirflowRatioField.fromCoolingRatio(cooling_ratio)` |  |  | `resources/hvac.rb`, `resources/epmodel.rb` | Compatibility façade stores the cooling ratio and leaves the heating ratio for that speed as `Autosize`. |
| `UnitarySystemPerformanceMultispeed.new(model)` |  |  | `resources/hvac.rb`, `resources/epmodel.rb` | Compatibility façade stores the mode and supply-airflow ratio fields; EPModel lacks this class. |
| `UnitarySystemPerformanceMultispeed#setSingleModeOperation(value)` |  |  | `resources/hvac.rb`, `resources/epmodel.rb` | Compatibility façade stores the setting for serialization into the EnergyPlus object. |
| `UnitarySystemPerformanceMultispeed#addSupplyAirflowRatioField(field)` |  |  | `resources/hvac.rb`, `resources/epmodel.rb` | Compatibility façade collects per-speed ratios for serialization into extensible groups. |
| `AirLoopHVACUnitarySystem#setDesignSpecificationMultispeedObject(performance)` |  |  | `resources/hvac.rb`, `resources/epmodel.rb` | Class-level override creates an EnergyPlus `UnitarySystemPerformance:Multispeed` object with speed counts, mode, no-load ratio, and per-speed ratios, then sets the unitary's object type and name references. Missing per-speed ratios are written as `Autosize`. |
| `WaterUseConnections#waterUseEquipment` | Yes |  | `resources/waterheater.rb`, `resources/epmodel.rb` | The native vector is not iterable from Ruby. The override resolves each equipment reference at group-local field index 0, not the parent field index, so the combi source-pump EMS includes water draws. |
| `WaterUseEquipment#flowRateFractionSchedule` |  |  | `resources/waterheater.rb`, `resources/epmodel.rb` | Shim resolves the flow-rate fraction schedule pointer and returns an optional schedule. |
| `WaterUseEquipment#targetTemperatureSchedule` |  |  | `resources/waterheater.rb`, `resources/epmodel.rb` | Shim resolves the target-temperature schedule pointer. An unset pointer returns an empty optional, preserving the combi EMS fallback to the heater setpoint schedule. |
| `WeatherFile.setWeatherFile(model, epw_file)` |  |  | `resources/location.rb` | Called only when `Version::UseEPModel` is false. For EPModel, `meta_measure.rb` retains the EPW path through runner reset and passes it to EnergyPlus with `-w`. |
| `YearDescription#assumedYear` |  |  | `resources/schedules.rb` | Used only on the OpenStudio 3.11 branch; EPModel reads RunPeriod Begin Year instead. |
| `YearDescription#setCalendarYear` |  |  | `resources/location.rb` | Used only on the OpenStudio 3.11 branch; EPModel writes RunPeriod year fields instead. |
| `ZoneCapacitanceMultiplierResearchSpecial#setHumidityCapacityMultiplier` | Yes | Yes | `resources/simcontrols.rb` | |
| `ZoneCapacitanceMultiplierResearchSpecial#setTemperatureCapacityMultiplier` | Yes | Yes | `resources/simcontrols.rb` | |
| `ZoneHVACBaseboardConvectiveWater#heatingCoil` | Yes |  | `resources/hvac.rb`, `resources/epmodel.rb` | EPModel stores the baseboard coil as a transient child, so the EPModel branch attaches the baseboard to the zone before adding its child coil to the plant loop. The legacy branch continues attaching the original coil object. |
| `ZoneHVACDehumidifierDX#setAvailabilitySchedule(schedule)` | Yes |  | `resources/hvac.rb`, `resources/epmodel.rb` | EPModel's native setter does not preserve the schedule pointer; a class-level override writes the `Availability Schedule Name` pointer directly. |
| `ZoneHVACFourPipeFanCoil.new(model, schedule, fan, cooling_coil, heating_coil)` |  |  | `resources/hvac.rb`, `resources/epmodel.rb` | Class-level shim calls EPModel's model-only constructor, then sets the availability schedule, supply fan, cooling coil, and heating coil. |
