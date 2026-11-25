# frozen_string_literal: true

require 'date'
require_relative 'version'

if Version::UseEPModel
  OpenStudio.send(:remove_const, :Model)
  OpenStudio.const_set(:Model, OpenStudio::EPModel)

  module EPModelCompatibility
    def self.set_pointer(object, field_name, target)
      field_index = object.iddObject.getFieldIndex(field_name)
      field_index.is_initialized && object.setPointer(field_index.get, target.handle)
    end

    def self.get_schedule(object, field_name)
      field_index = object.iddObject.getFieldIndex(field_name)
      return OpenStudio::EPModel::OptionalSchedule.new unless field_index.is_initialized

      target = object.getTarget(field_index.get)
      return OpenStudio::EPModel::OptionalSchedule.new unless target.is_initialized

      target.get.to_Schedule
    end

    def self.get_boiler_hot_waters(model)
      model.getModelObjects.select do |object|
        object.iddObject.name.to_s == 'Boiler:HotWater'
      end.map do |object|
        object.to_BoilerHotWater.get
      end
    end

    def self.get_water_use_equipments(water_use_connections)
      field_index = water_use_connections.iddObject.getFieldIndex('Water Use Equipment Name')
      raise "Could not find Water Use Equipment Name field for '#{water_use_connections.name}'." unless field_index.is_initialized

      water_use_equipments = []
      water_use_connections.numExtensibleGroups.times do |index|
        group = water_use_connections.getExtensibleGroup(index).to_WorkspaceExtensibleGroup
        next unless group.is_initialized

        # Extensible-group fields use local indices, unlike the parent object's field index.
        target = group.get.getTarget(0)
        next unless target.is_initialized

        water_use_equipment = target.get.to_WaterUseEquipment
        water_use_equipments << water_use_equipment.get if water_use_equipment.is_initialized
      end
      return water_use_equipments
    end

    class MultiSpeedCoilStageData
      def initialize(_model, *curves)
        raise 'Expected 6 performance curves for multi-speed coil stage.' unless curves.size == 6

        @curve_names = curves.map { |curve| curve.name.to_s }
      end

      def curve_names
        @curve_names
      end
    end

    class CoilCoolingDXMultiSpeedStageData < MultiSpeedCoilStageData
      def setGrossRatedCoolingCOP(value)
        @cop = value
      end

      def setGrossRatedSensibleHeatRatio(value)
        @sensible_heat_ratio = value
      end

      def setNominalTimeforCondensateRemovaltoBegin(value)
        @condensate_removal_time = value
      end

      def setRatioofInitialMoistureEvaporationRateandSteadyStateLatentCapacity(value)
        @initial_moisture_evaporation_ratio = value
      end

      def setRatedWasteHeatFractionofPowerInput(value)
        @waste_heat_fraction = value
      end

      def setMaximumCyclingRate(value)
        @maximum_cycling_rate = value
      end

      def setLatentCapacityTimeConstant(value)
        @latent_capacity_time_constant = value
      end

      def setGrossRatedTotalCoolingCapacity(value)
        @capacity = value
      end

      def setRatedAirFlowRate(value)
        @airflow = value
      end

      def grossRatedTotalCoolingCapacity
        OpenStudio::OptionalDouble.new(@capacity)
      end

      def ratedAirFlowRate
        OpenStudio::OptionalDouble.new(@airflow)
      end

      def idf_fields
        [
          @capacity,
          @sensible_heat_ratio,
          @cop,
          @airflow,
          773.3,
          934.4
        ] + curve_names[0, 5] + [
          @condensate_removal_time,
          @initial_moisture_evaporation_ratio,
          @maximum_cycling_rate,
          @latent_capacity_time_constant,
          @waste_heat_fraction,
          curve_names[5],
          0.9,
          'Autosize',
          'Autosize'
        ]
      end
    end

    class CoilHeatingDXMultiSpeedStageData < MultiSpeedCoilStageData
      def setGrossRatedHeatingCOP(value)
        @cop = value
      end

      def setRatedWasteHeatFractionofPowerInput(value)
        @waste_heat_fraction = value
      end

      def setGrossRatedHeatingCapacity(value)
        @capacity = value
      end

      def setRatedAirFlowRate(value)
        @airflow = value
      end

      def grossRatedHeatingCapacity
        OpenStudio::OptionalDouble.new(@capacity)
      end

      def ratedAirFlowRate
        OpenStudio::OptionalDouble.new(@airflow)
      end

      def idf_fields
        [
          @capacity,
          @cop,
          @airflow,
          773.3,
          934.4
        ] + curve_names[0, 5] + [
          @waste_heat_fraction,
          curve_names[5]
        ]
      end
    end

    class WaterToAirHeatPumpSpeed
      def initialize(group, fields, mode)
        @group = group.to_WorkspaceExtensibleGroup.get
        @fields = fields
        @capacity_curve_field = "Speed Total #{mode} Capacity Function of Air Flow Fraction Curve Name"
      end

      def referenceUnitRatedWaterFlowRate
        @group.getDouble(@fields.fetch('Speed Reference Unit Rated Water Flow Rate')).get
      end

      def referenceUnitRatedAirFlowRate
        @group.getDouble(@fields.fetch('Speed Reference Unit Rated Air Flow Rate')).get
      end
      alias referenceUnitRatedAirFlow referenceUnitRatedAirFlowRate

      def totalHeatingCapacityFunctionofAirFlowFractionCurve
        @group.getTarget(@fields.fetch(@capacity_curve_field)).get
      end
      alias totalCoolingCapacityFunctionofAirFlowFractionCurve totalHeatingCapacityFunctionofAirFlowFractionCurve

      def energyInputRatioFunctionofAirFlowFractionCurve
        @group.getTarget(@fields.fetch('Speed Energy Input Ratio Function of Air Flow Fraction Curve Name')).get
      end
    end

    class SupplyAirflowRatioField
      attr_reader :heating_ratio, :cooling_ratio

      def initialize(heating_ratio = nil, cooling_ratio = nil)
        @heating_ratio = heating_ratio
        @cooling_ratio = cooling_ratio
      end

      def self.fromHeatingRatio(heating_ratio)
        new(heating_ratio)
      end

      def self.fromCoolingRatio(cooling_ratio)
        new(nil, cooling_ratio)
      end
    end

    class UnitarySystemPerformanceMultispeed
      attr_reader :model, :supply_airflow_ratio_fields

      def initialize(model)
        @model = model
        @supply_airflow_ratio_fields = []
        @single_mode_operation = false
      end

      def setSingleModeOperation(single_mode_operation)
        @single_mode_operation = single_mode_operation
        true
      end

      def addSupplyAirflowRatioField(ratio_field)
        unless ratio_field.is_a?(SupplyAirflowRatioField)
          raise 'Expected SupplyAirflowRatioField.'
        end

        @supply_airflow_ratio_fields << ratio_field
        true
      end

      def single_mode_operation
        @single_mode_operation
      end
    end

    def self.add_multispeed_coil_stage(coil, stage_fields)
      group = coil.pushExtensibleGroup
      stage_fields.each_with_index do |value, index|
        if value.is_a?(String)
          field_set = group.setString(index, value)
        else
          field_set = group.setDouble(index, value)
        end
        raise "Could not set stage field #{index} for coil '#{coil.name}'." unless field_set
      end

      number_of_speeds_field = coil.iddObject.getFieldIndex('Number of Speeds')
      raise "Could not find Number of Speeds field for coil '#{coil.name}'." unless number_of_speeds_field.is_initialized

      number_of_speeds = coil.numExtensibleGroups
      if number_of_speeds > 1
        unless coil.setInt(number_of_speeds_field.get, number_of_speeds)
          raise "Could not set Number of Speeds for coil '#{coil.name}'."
        end
      end
    end

    def self.record_multispeed_coil_stage(coil, stage)
      if @multispeed_coil_stages_by_handle.nil?
        @multispeed_coil_stages_by_handle = {}
      end

      stages = @multispeed_coil_stages_by_handle[coil.handle.to_s]
      if stages.nil?
        stages = []
        @multispeed_coil_stages_by_handle[coil.handle.to_s] = stages
      end
      stages << stage
    end

    def self.multispeed_coil_stages(coil)
      return [] if @multispeed_coil_stages_by_handle.nil?

      stages = @multispeed_coil_stages_by_handle[coil.handle.to_s]
      return [] if stages.nil?

      stages.dup
    end

    def self.add_unitary_system_performance_multispeed(unitary, performance)
      ratio_fields = performance.supply_airflow_ratio_fields
      raise "Unitary system '#{unitary.name}' has no supply airflow ratios." if ratio_fields.empty?

      heating_speed_count = ratio_fields.count { |ratio_field| !ratio_field.heating_ratio.nil? }
      heating_speed_count = 1 if heating_speed_count == 0
      cooling_speed_count = ratio_fields.count { |ratio_field| !ratio_field.cooling_ratio.nil? }
      cooling_speed_count = 1 if cooling_speed_count == 0

      performance_idd_type = OpenStudio::IddObjectType.new('UnitarySystemPerformance_Multispeed')
      performance_object = OpenStudio::IdfObject.new(performance_idd_type)
      performance_name = "#{unitary.name} Unitary System Performance"
      unless performance_object.setName(performance_name).is_initialized
        raise "Could not name UnitarySystemPerformance:Multispeed for '#{unitary.name}'."
      end

      fields = {
        'Number of Speeds for Heating' => heating_speed_count,
        'Number of Speeds for Cooling' => cooling_speed_count,
        'Single Mode Operation' => performance.single_mode_operation ? 'Yes' : 'No',
        'No Load Supply Air Flow Rate Ratio' => 1.0
      }
      fields.each do |field_name, value|
        field_index = performance_object.iddObject.getFieldIndex(field_name)
        raise "Could not find '#{field_name}' field for '#{performance_name}'." unless field_index.is_initialized

        if value.is_a?(Integer)
          field_set = performance_object.setInt(field_index.get, value)
        elsif value.is_a?(Numeric)
          field_set = performance_object.setDouble(field_index.get, value)
        else
          field_set = performance_object.setString(field_index.get, value)
        end
        raise "Could not set '#{field_name}' for '#{performance_name}'." unless field_set
      end

      ratio_fields.each do |ratio_field|
        group = performance_object.pushExtensibleGroup
        [ratio_field.heating_ratio, ratio_field.cooling_ratio].each_with_index do |ratio, index|
          if ratio.nil?
            field_set = group.setString(index, 'Autosize')
          else
            field_set = group.setDouble(index, ratio)
          end
          raise "Could not set supply airflow ratio #{index} for '#{performance_name}'." unless field_set
        end
      end

      performance_object = performance.model.addObject(performance_object)
      raise "Could not add '#{performance_name}' to the model." unless performance_object.is_initialized

      type_field = unitary.iddObject.getFieldIndex('Design Specification Multispeed Object Type')
      raise "Could not find Design Specification Multispeed Object Type field for '#{unitary.name}'." unless type_field.is_initialized
      unless unitary.setString(type_field.get, 'UnitarySystemPerformance:Multispeed')
        raise "Could not set Design Specification Multispeed Object Type for '#{unitary.name}'."
      end
      unless set_pointer(unitary, 'Design Specification Multispeed Object Name', performance_object.get)
        raise "Could not set Design Specification Multispeed Object Name for '#{unitary.name}'."
      end
    end

    def self.add_cooling_dx_multispeed_stage(coil, stage)
      unless stage.is_a?(CoilCoolingDXMultiSpeedStageData)
        raise "Expected CoilCoolingDXMultiSpeedStageData for coil '#{coil.name}'."
      end

      add_multispeed_coil_stage(coil, stage.idf_fields)
      record_multispeed_coil_stage(coil, stage)
    end

    def self.add_heating_dx_multispeed_stage(coil, stage)
      unless stage.is_a?(CoilHeatingDXMultiSpeedStageData)
        raise "Expected CoilHeatingDXMultiSpeedStageData for coil '#{coil.name}'."
      end

      add_multispeed_coil_stage(coil, stage.idf_fields)
      record_multispeed_coil_stage(coil, stage)
    end

    unless OpenStudio::Model.const_defined?(:CoilCoolingDXMultiSpeedStageData, false)
      OpenStudio::Model.const_set(:CoilCoolingDXMultiSpeedStageData, CoilCoolingDXMultiSpeedStageData)
    end
    unless OpenStudio::Model.const_defined?(:CoilHeatingDXMultiSpeedStageData, false)
      OpenStudio::Model.const_set(:CoilHeatingDXMultiSpeedStageData, CoilHeatingDXMultiSpeedStageData)
    end
    unless OpenStudio::Model.const_defined?(:SupplyAirflowRatioField, false)
      OpenStudio::Model.const_set(:SupplyAirflowRatioField, SupplyAirflowRatioField)
    end
    unless OpenStudio::Model.const_defined?(:UnitarySystemPerformanceMultispeed, false)
      OpenStudio::Model.const_set(:UnitarySystemPerformanceMultispeed, UnitarySystemPerformanceMultispeed)
    end

    unless OpenStudio::Model::CoilCoolingDXMultiSpeed.method_defined?(:addStage)
      OpenStudio::Model::CoilCoolingDXMultiSpeed.class_eval do
        def addStage(stage)
          EPModelCompatibility.add_cooling_dx_multispeed_stage(self, stage)
        end
      end
    end
    unless OpenStudio::Model::CoilHeatingDXMultiSpeed.method_defined?(:addStage)
      OpenStudio::Model::CoilHeatingDXMultiSpeed.class_eval do
        def addStage(stage)
          EPModelCompatibility.add_heating_dx_multispeed_stage(self, stage)
        end
      end
    end

    unless OpenStudio::Model::CoilCoolingDXMultiSpeed.method_defined?(:stages)
      OpenStudio::Model::CoilCoolingDXMultiSpeed.class_eval do
        def stages
          EPModelCompatibility.multispeed_coil_stages(self)
        end
      end
    end
    unless OpenStudio::Model::CoilHeatingDXMultiSpeed.method_defined?(:stages)
      OpenStudio::Model::CoilHeatingDXMultiSpeed.class_eval do
        def stages
          EPModelCompatibility.multispeed_coil_stages(self)
        end
      end
    end
    unless OpenStudio::Model::AirLoopHVACUnitarySystem.method_defined?(:setDesignSpecificationMultispeedObject)
      OpenStudio::Model::AirLoopHVACUnitarySystem.class_eval do
        def setDesignSpecificationMultispeedObject(performance)
          unless performance.is_a?(EPModelCompatibility::UnitarySystemPerformanceMultispeed)
            raise 'Expected UnitarySystemPerformanceMultispeed.'
          end

          EPModelCompatibility.add_unitary_system_performance_multispeed(self, performance)
          true
        end
      end
    end

    def self.get_scheduled_setpoint_managers(node)
      node.model.getModelObjects.select do |object|
        next false unless object.iddObject.name.to_s == 'SetpointManager:Scheduled'

        setpoint_manager = object.to_SetpointManagerScheduled
        next false unless setpoint_manager.is_initialized

        setpoint_node = setpoint_manager.get.setpointNode
        setpoint_node.is_initialized && setpoint_node.get.handle.to_s == node.handle.to_s
      end.map do |object|
        object.to_SetpointManagerScheduled.get
      end
    end

    def self.workspace_field_string(object, field_name)
      field_index = object.iddObject.getFieldIndex(field_name)
      return unless field_index.is_initialized

      value = object.getString(field_index.get)
      value.is_initialized ? value.get : nil
    end

    def self.remove_unused_schedule_constants(workspace)
      ems_schedule_names = []
      {
        'EnergyManagementSystem:Sensor' => 'Output:Variable or Output:Meter Index Key Name',
        'EnergyManagementSystem:Actuator' => 'Actuated Component Unique Name'
      }.each do |object_type, field_name|
        workspace.getObjectsByType(object_type.to_IddObjectType).each do |object|
          schedule_name = workspace_field_string(object, field_name)
          ems_schedule_names << schedule_name.downcase unless schedule_name.nil?
        end
      end

      workspace.getObjectsByType('Schedule_Constant'.to_IddObjectType).each do |schedule|
        schedule_name = workspace_field_string(schedule, 'Name')
        next unless schedule.sources.empty?
        next if schedule_name.nil?
        next if ems_schedule_names.include?(schedule_name.downcase)

        raise "Could not remove unused Schedule:Constant '#{schedule_name}'." unless schedule.remove
      end
    end

    def self.get_boiler_plant_loop(model, boiler)
      model.getPlantLoops.find do |candidate|
        candidate.supplyComponents.any? { |component| component.handle.to_s == boiler.handle.to_s }
      end || fail("Could not find PlantLoop for boiler '#{boiler.name}'.")
    end

    def self.build_boiler_plant_loop_copy(model, plant_loop)
      boiler = plant_loop.supplyComponents.find { |component| component.to_BoilerHotWater.is_initialized }
      raise "Could not find BoilerHotWater on PlantLoop '#{plant_loop.name}'." if boiler.nil?

      boiler = clone_model_object(boiler.to_BoilerHotWater.get, model).to_BoilerHotWater
      raise "Could not clone BoilerHotWater on PlantLoop '#{plant_loop.name}'." unless boiler.is_initialized

      boiler = boiler.get

      plant_loop_copy = OpenStudio::Model::PlantLoop.new(model)
      raise "Could not name copied boiler PlantLoop '#{plant_loop.name}'." unless plant_loop_copy.setName("#{plant_loop.name} DHW")

      copy_boiler_plant_loop_properties(plant_loop, plant_loop_copy)

      pump = plant_loop.supplyComponents.find { |component| component.to_PumpVariableSpeed.is_initialized }
      unless pump.nil?
        source_pump = pump.to_PumpVariableSpeed.get
        pump = clone_model_object(source_pump, model).to_PumpVariableSpeed
        raise "Could not clone pump on PlantLoop '#{plant_loop.name}'." unless pump.is_initialized

        pump = pump.get
        pump_name_number = 1
        pump_name = "#{source_pump.name} #{pump_name_number}"
        while model.getModelObjects.any? { |object| object.name.to_s.casecmp(pump_name).zero? }
          pump_name_number += 1
          pump_name = "#{source_pump.name} #{pump_name_number}"
        end
        raise "Could not name cloned pump on PlantLoop '#{plant_loop_copy.name}'." unless pump.setName(pump_name)
        raise "Could not attach cloned pump to PlantLoop '#{plant_loop_copy.name}'." unless pump.addToNode(plant_loop_copy.supplyInletNode)
      end
      raise "Could not attach cloned boiler to PlantLoop '#{plant_loop_copy.name}'." unless plant_loop_copy.addSupplyBranchForComponent(boiler)

      supply_bypass = Model.add_pipe_adiabatic(model)
      raise "Could not add supply bypass to PlantLoop '#{plant_loop_copy.name}'." unless plant_loop_copy.addSupplyBranchForComponent(supply_bypass)

      supply_outlet_pipe = Model.add_pipe_adiabatic(model)
      raise "Could not add supply outlet pipe to PlantLoop '#{plant_loop_copy.name}'." unless supply_outlet_pipe.addToNode(plant_loop_copy.supplyOutletNode)

      demand_bypass = Model.add_pipe_adiabatic(model)
      raise "Could not add demand bypass to PlantLoop '#{plant_loop_copy.name}'." unless plant_loop_copy.addDemandBranchForComponent(demand_bypass)

      demand_inlet_pipe = Model.add_pipe_adiabatic(model)
      raise "Could not add demand inlet pipe to PlantLoop '#{plant_loop_copy.name}'." unless demand_inlet_pipe.addToNode(plant_loop_copy.demandInletNode)

      demand_outlet_pipe = Model.add_pipe_adiabatic(model)
      raise "Could not add demand outlet pipe to PlantLoop '#{plant_loop_copy.name}'." unless demand_outlet_pipe.addToNode(plant_loop_copy.demandOutletNode)

      sizing_plant = plant_loop_copy.sizingPlant
      setpoint_schedule = Model.add_schedule_constant(
        model,
        name: "#{plant_loop_copy.name} setpoint",
        value: sizing_plant.designLoopExitTemperature,
        limits: EPlus::ScheduleTypeLimitsTemperature
      )
      setpoint_manager = OpenStudio::Model::SetpointManagerScheduled.new(model, setpoint_schedule)
      raise "Could not add setpoint manager to PlantLoop '#{plant_loop_copy.name}'." unless setpoint_manager.addToNode(plant_loop_copy.supplyOutletNode)

      return plant_loop_copy
    end

    def self.add_baseboard_coil_to_plant_loop(plant_loop, baseboard, thermal_zone)
      raise "Could not add baseboard '#{baseboard.name}' to ThermalZone '#{thermal_zone.name}'." unless baseboard.addToThermalZone(thermal_zone)

      heating_coil = baseboard.heatingCoil.to_CoilHeatingWaterBaseboard
      raise "Could not find heating coil for baseboard '#{baseboard.name}'." unless heating_coil.is_initialized
      raise "Could not add baseboard coil for '#{baseboard.name}' to PlantLoop '#{plant_loop.name}'." unless plant_loop.addDemandBranchForComponent(heating_coil.get)
    end

    def self.copy_boiler_plant_loop_properties(source, target)
      target.setLoadDistributionScheme(source.loadDistributionScheme)
      target.setFluidType(source.fluidType)
      target.setGlycolConcentration(source.glycolConcentration) if source.fluidType == EPlus::FluidPropyleneGlycol
      target.setMaximumLoopTemperature(source.maximumLoopTemperature)
      target.setMinimumLoopTemperature(source.minimumLoopTemperature)
      if source.isMaximumLoopFlowRateAutosized
        target.autosizeMaximumLoopFlowRate
      elsif source.maximumLoopFlowRate.is_initialized
        target.setMaximumLoopFlowRate(source.maximumLoopFlowRate.get)
      end
      if source.isMinimumLoopFlowRateAutosized
        target.autosizeMinimumLoopFlowRate
      elsif source.minimumLoopFlowRate.is_initialized
        target.setMinimumLoopFlowRate(source.minimumLoopFlowRate.get)
      end
      if source.isPlantLoopVolumeAutocalculated
        target.autocalculatePlantLoopVolume
      elsif source.plantLoopVolume.is_initialized
        target.setPlantLoopVolume(source.plantLoopVolume.get)
      end
      target.setCommonPipeSimulation(source.commonPipeSimulation) unless source.isCommonPipeSimulationDefaulted

      source_sizing = source.sizingPlant
      target_sizing = target.sizingPlant
      target_sizing.setLoopType(source_sizing.loopType)
      target_sizing.setDesignLoopExitTemperature(source_sizing.designLoopExitTemperature)
      target_sizing.setLoopDesignTemperatureDifference(source_sizing.loopDesignTemperatureDifference)
      target_sizing.setSizingOption(source_sizing.sizingOption)
      target_sizing.setZoneTimestepsinAveragingWindow(source_sizing.zoneTimestepsinAveragingWindow)
      target_sizing.setCoincidentSizingFactorMode(source_sizing.coincidentSizingFactorMode)

      raise "Could not copy availability managers for PlantLoop '#{target.name}'." unless target.setAvailabilityManagers(source.availabilityManagers)
    end

    def self.clone_model_object(object, model)
      cloned_object = model.addObject(object.idfObject.clone(false))
      raise "Could not clone #{object.iddObject.name} '#{object.name}'." unless cloned_object.is_initialized

      return cloned_object.get
    end

    def self.set_default_schedule_type_limits(schedule, limits_name)
      return if schedule.scheduleTypeLimits.is_initialized

      limits = schedule.model.getScheduleTypeLimitss.find { |candidate| candidate.name.to_s == limits_name }
      if limits.nil?
        limits = OpenStudio::EPModel::ScheduleTypeLimits.new(schedule.model)
        raise "Could not name schedule type limits '#{limits_name}'." unless limits.setName(limits_name)
        raise "Could not set lower limit for '#{limits_name}'." unless limits.setLowerLimitValue(0)

        if limits_name == 'Fractional'
          raise "Could not set upper limit for '#{limits_name}'." unless limits.setUpperLimitValue(1)
        elsif limits_name == 'ActivityLevel'
          raise "Could not set unit type for '#{limits_name}'." unless limits.setUnitType('ActivityLevel')
        else
          raise "Unexpected schedule type limits '#{limits_name}'."
        end
        raise "Could not set numeric type for '#{limits_name}'." unless limits.setNumericType('Continuous')
      end
      raise "Could not set schedule type limits on '#{schedule.name}'." unless schedule.setScheduleTypeLimits(limits)
    end

    class AdditionalProperties
      def self.for_object(object)
        @features_by_handle ||= {}
        return new(@features_by_handle[object.handle.to_s] ||= {})
      end

      # Copies features to an object added to another model (handles change when objects are copied).
      def self.copy_features(from_object, to_object)
        @features_by_handle ||= {}
        features = @features_by_handle[from_object.handle.to_s]
        return if features.nil? || features.empty?

        @features_by_handle[to_object.handle.to_s] = features.dup
      end

      def initialize(features)
        @features = features
      end

      def setFeature(name, value)
        if not [String, Integer, Float, TrueClass, FalseClass].any? { |value_class| value.is_a?(value_class) }
          raise TypeError, "Unsupported feature value type: #{value.class}"
        end

        if value.is_a?(String)
          value = value.dup
        end
        @features[name] = value
        return true
      end

      { getFeatureAsString: [[String], OpenStudio::OptionalString],
        getFeatureAsInteger: [[Integer], OpenStudio::OptionalInt],
        getFeatureAsDouble: [[Float], OpenStudio::OptionalDouble],
        getFeatureAsBoolean: [[TrueClass, FalseClass], OpenStudio::OptionalBool] }.each do |method_name, (value_classes, optional_class)|
        define_method(method_name) do |name|
          value = @features[name]
          if value_classes.any? { |value_class| value.is_a?(value_class) }
            return optional_class.new(value)
          end

          return optional_class.new
        end
      end
    end

    class InternalMassDefinition
      def initialize(model)
        vertices = [OpenStudio::Point3d.new(0, 0, 0),
                    OpenStudio::Point3d.new(1, 0, 0),
                    OpenStudio::Point3d.new(1, 1, 0),
                    OpenStudio::Point3d.new(0, 1, 0)]
        @surface = OpenStudio::EPModel::InteriorPartitionSurface.new(vertices, model)
      end

      def setName(name)
        @surface.setName(name)
      end

      def setSurfaceArea(area)
        @surface.setSurfaceArea(area)
      end

      def setSpace(space)
        EPModelCompatibility.set_pointer(@surface, 'Space or SpaceList Name', space)
      end

      def setConstruction(construction)
        @surface.setConstruction(construction)
      end

      def adjacentSurface
        OpenStudio::EPModel::OptionalSurface.new
      end

      def name
        @surface.name
      end
    end

    class InternalMass
      def initialize(definition)
        @definition = definition
      end

      def setName(name)
        @definition.setName(name)
      end

      def setSpace(space)
        @definition.setSpace(space)
      end

      def internalMassDefinition
        @definition
      end
    end

    class OtherEquipmentDefinition
      def initialize(model)
        @equipment = OpenStudio::EPModel::OtherEquipment.new(model)
      end

      def equipment
        @equipment
      end

      def setName(name)
        @equipment.setName(name)
      end

      def setDesignLevel(value)
        @equipment.setDesignLevel(value)
      end

      def setFractionRadiant(value)
        @equipment.setFractionRadiant(value)
      end

      def setFractionLatent(value)
        @equipment.setFractionLatent(value)
      end

      def setFractionLost(value)
        @equipment.setFractionLost(value)
      end
    end

    class ElectricEquipmentDefinition
      def initialize(model)
        @equipment = OpenStudio::EPModel::ElectricEquipment.new(model)
      end

      def equipment
        @equipment
      end

      def setName(name)
        @equipment.setName(name)
      end

      def setDesignLevel(value)
        @equipment.setDesignLevel(value)
      end

      def setFractionRadiant(value)
        @equipment.setFractionRadiant(value)
      end

      def setFractionLatent(value)
        @equipment.setFractionLatent(value)
      end

      def setFractionLost(value)
        @equipment.setFractionLost(value)
      end
    end

    class WaterUseEquipmentDefinition
      def initialize(model)
        @equipment = OpenStudio::EPModel::WaterUseEquipment.new(model)
      end

      def equipment
        @equipment
      end

      def setName(name)
        @equipment.setName(name)
      end

      def setPeakFlowRate(value)
        @equipment.setPeakFlowRate(value)
      end

      def setEndUseSubcategory(value)
        @equipment.setEndUseSubcategory(value)
      end

      def setTargetTemperatureSchedule(schedule)
        EPModelCompatibility.set_pointer(@equipment, 'Target Temperature Schedule Name', schedule)
      end
    end

    class LightsDefinition
      def initialize(model)
        @lights = OpenStudio::EPModel::Lights.new(model)
      end

      def lights
        @lights
      end

      def setName(name)
        @lights.setName(name)
      end

      def setLightingLevel(value)
        @lights.setLightingLevel(value)
      end

      def setFractionRadiant(value)
        @lights.setFractionRadiant(value)
      end

      def setFractionVisible(value)
        @lights.setFractionVisible(value)
      end

      def setReturnAirFraction(value)
        @lights.setReturnAirFraction(value)
      end
    end

    class PeopleDefinition
      def initialize(model)
        @people = OpenStudio::EPModel::People.new(model)
      end

      def people
        @people
      end

      def setName(name)
        @people.setName(name)
      end

      def setNumberofPeople(value)
        set_double_field('Number of People', value)
      end

      def setFractionRadiant(value)
        set_double_field('Fraction Radiant', value)
      end

      def setSensibleHeatFraction(value)
        set_double_field('Sensible Heat Fraction', value)
      end

      def setMeanRadiantTemperatureCalculationType(value)
        set_string_field('Mean Radiant Temperature Calculation Type', value)
      end

      def setCarbonDioxideGenerationRate(value)
        set_double_field('Carbon Dioxide Generation Rate', value)
      end

      def setEnableASHRAE55ComfortWarnings(value)
        set_string_field('Enable ASHRAE 55 Comfort Warnings', value ? 'Yes' : 'No')
      end

      private

      def set_double_field(name, value)
        field_index = @people.iddObject.getFieldIndex(name)
        field_index.is_initialized && @people.setDouble(field_index.get, value)
      end

      def set_string_field(name, value)
        field_index = @people.iddObject.getFieldIndex(name)
        field_index.is_initialized && @people.setString(field_index.get, value)
      end
    end

    class OutputMeter
      def initialize(model_or_object)
        if model_or_object.is_a?(OpenStudio::EPModel::Model)
          meter_type = OpenStudio::IddObjectType.new('Output_Meter')
          @object = model_or_object.addObject(OpenStudio::IdfObject.new(meter_type)).get
        else
          @object = model_or_object
        end
      end

      def name
        field_index = @object.iddObject.getFieldIndex('Key Name')
        @object.getString(field_index.get).get
      end

      def setName(name)
        field_index = @object.iddObject.getFieldIndex('Key Name')
        field_index.is_initialized && @object.setString(field_index.get, name)
      end

      def reportingFrequency
        field_index = @object.iddObject.getFieldIndex('Reporting Frequency')
        @object.getString(field_index.get).get
      end

      def setReportingFrequency(frequency)
        field_index = @object.iddObject.getFieldIndex('Reporting Frequency')
        field_index.is_initialized && @object.setString(field_index.get, frequency)
      end
    end

    class MonthlyVariableGroup
      def initialize(group)
        @group = group
      end

      def variableOrMeterName
        @group.getString(0).get
      end

      def aggregationType
        @group.getString(1).get
      end
    end

    class OptionalMonthlyVariableGroup
      def initialize(group)
        @group = group
      end

      def is_initialized
        !@group.nil?
      end

      def get
        @group
      end
    end

    class ShadingSurface
      def initialize(object)
        @object = object
      end

      def additionalProperties
        AdditionalProperties.for_object(@object)
      end

      def vertices
        vertices = OpenStudio::Point3dVector.new
        @object.extensibleGroups.each do |group|
          coordinates = (0..2).map do |index|
            value = group.getDouble(index)
            next unless value.is_initialized

            value.get
          end
          next if coordinates.any?(&:nil?)

          vertices << OpenStudio::Point3d.new(*coordinates)
        end
        vertices
      end

      def setVertices(vertices)
        @object.clearExtensibleGroups
        vertices.each do |vertex|
          group = @object.pushExtensibleGroup
          fields_set = group.setDouble(0, vertex.x)
          fields_set &&= group.setDouble(1, vertex.y)
          fields_set &&= group.setDouble(2, vertex.z)
          unless fields_set
            @object.clearExtensibleGroups
            return false
          end
        end
        true
      end
    end

    class ShadingSurfaceGroup
      def initialize(model, object)
        @model = model
        @object = object
      end

      def name
        @object.nameString
      end

      def shadingSurfaces
        surface_type = OpenStudio::IddObjectType.new('OS_ShadingSurface')
        group_handle = @object.handle.to_s
        @model.getObjectsByType(surface_type).filter_map do |surface|
          field_index = surface.iddObject.getFieldIndex('Shading Surface Group Name')
          next unless field_index.is_initialized

          target = surface.getTarget(field_index.get)
          next unless target.is_initialized && target.get.handle.to_s == group_handle

          ShadingSurface.new(surface)
        end
      end

      def space
        field_index = @object.iddObject.getFieldIndex('Space Name')
        return OpenStudio::EPModel::OptionalSpace.new unless field_index.is_initialized

        target = @object.getTarget(field_index.get)
        return OpenStudio::EPModel::OptionalSpace.new unless target.is_initialized

        target.get.to_Space
      end

      def shadesSubSurface?(subsurface)
        field_index = @object.iddObject.getFieldIndex('Shaded Object Name')
        return false unless field_index.is_initialized

        target = @object.getTarget(field_index.get)
        target.is_initialized && target.get.handle.to_s == subsurface.handle.to_s
      end
    end

    class AirTerminalSingleDuctUncontrolled
      def self.new(model, schedule)
        OpenStudio::EPModel::AirTerminalSingleDuctConstantVolumeNoReheat.new(model, schedule)
      end
    end

    def self.normalize_workspace(workspace, model)
      add_global_geometry_rules(workspace)
      add_output_sqlite(workspace)
      add_output_table_defaults(workspace)
      normalize_surface_types(workspace)
      normalize_people_temperature_type(workspace)
      declare_ems_output_globals(workspace)
      repair_demand_branch_endpoints(workspace)
      normalize_boiler_load_distribution(workspace)
      add_ground_heat_exchanger_plant_schemes(workspace, model)
      add_default_heating_plant_schemes(workspace, model)
      normalize_desuperheater_tank_outlets(workspace)
      normalize_wrapped_hpwh_plant_references(workspace)
    end

    def self.normalize_desuperheater_tank_outlets(workspace)
      targets = {}
      workspace.getObjectsByType('Coil:WaterHeating:Desuperheater'.to_IddObjectType).each do |coil|
        type = coil.getString(coil.iddObject.getFieldIndex('Tank Object Type').get).get
        name = coil.getString(coil.iddObject.getFieldIndex('Tank Name').get).get
        targets[[type.downcase, name.downcase]] = workspace.getObjectByTypeAndName(type.to_IddObjectType, name).get
      end
      return if targets.empty?

      workspace.getObjectsByType('Branch'.to_IddObjectType).each do |branch|
        branch.extensibleGroups.each_cons(2) do |upstream, downstream|
          tank = targets[[upstream.getString(0).to_s.downcase, upstream.getString(1).to_s.downcase]]
          next if tank.nil?
          next unless ['waterheater:mixed', 'waterheater:stratified'].include?(downstream.getString(0).to_s.downcase)

          # Inserting the main tank updates the branch outlet but not the preheat tank.
          outlet_index = tank.iddObject.getFieldIndex('Use Side Outlet Node Name').get
          outlet_node = upstream.to_WorkspaceExtensibleGroup.get.getTarget(3).get
          unless tank.setPointer(outlet_index, outlet_node.handle)
            fail "Could not update the use-side outlet for '#{tank.name}'."
          end
        end
      end
    end

    def self.detach_water_heater_branch_for_move(tank, node)
      loop = tank.plantLoop
      return unless loop.is_initialized

      plant_loop = loop.get
      branch_list = plant_loop.getTarget(plant_loop.iddObject.getFieldIndex('Plant Side Branch List Name').get).get
      equipment_groups = branch_list.extensibleGroups.to_a[1...-1]
      return if equipment_groups.nil?

      source_branch = nil
      destination_branch = nil
      equipment_groups.each do |group|
        branch = group.to_WorkspaceExtensibleGroup.get.getTarget(0).get
        branch.extensibleGroups.each do |component|
          next unless ['WaterHeater:Mixed', 'WaterHeater:Stratified'].include?(component.getString(0).to_s)

          entry = component.to_WorkspaceExtensibleGroup.get
          component_target = entry.getTarget(1)
          next unless component_target.is_initialized

          if component_target.get.handle == tank.handle
            source_branch = branch
          else
            outlet = entry.getTarget(3)
            destination_branch = branch if outlet.is_initialized && outlet.get.handle == node.handle
          end
        end
      end
      return if source_branch.nil? || destination_branch.nil? || source_branch.handle == destination_branch.handle
      return unless source_branch.numExtensibleGroups == 1

      # The native move detaches the tank but leaves the old branch in the loop.
      unless plant_loop.removeSupplyBranchWithComponent(tank)
        fail "Could not remove the original supply branch for '#{tank.name}'."
      end

      true
    end

    def self.normalize_wrapped_hpwh_plant_references(workspace)
      hpwh_type = 'WaterHeater:HeatPump:WrappedCondenser'
      tank_type = 'WaterHeater:Stratified'
      wrappers_by_tank = {}
      workspace.getObjectsByType(hpwh_type.to_IddObjectType).each do |hpwh|
        tank_name = hpwh.getString(hpwh.iddObject.getFieldIndex('Tank Name').get).get
        wrappers_by_tank[tank_name.downcase] = hpwh.name.to_s
      end
      return if wrappers_by_tank.empty?

      # The model connects the tank to the loop, but EnergyPlus dispatches the wrapper.
      ['Branch', 'PlantEquipmentList'].each do |object_type|
        workspace.getObjectsByType(object_type.to_IddObjectType).each do |object|
          object.extensibleGroups.each do |group|
            component_type = group.getString(0)
            component_name = group.getString(1)
            next unless component_type.is_initialized && component_type.get.casecmp(tank_type).zero?
            next unless component_name.is_initialized

            wrapper_name = wrappers_by_tank[component_name.get.downcase]
            next if wrapper_name.nil?

            unless group.setString(0, hpwh_type) && group.setString(1, wrapper_name)
              raise "Could not substitute wrapped heat pump water heater '#{wrapper_name}' in '#{object.name}'."
            end
          end
        end
      end
    end

    def self.add_global_geometry_rules(workspace)
      geometry_rules_type = OpenStudio::IddObjectType.new('GlobalGeometryRules')
      return unless workspace.getObjectsByType(geometry_rules_type).empty?

      geometry_rules = OpenStudio::IdfObject.new(geometry_rules_type)
      { 'Starting Vertex Position' => 'UpperLeftCorner',
        'Vertex Entry Direction' => 'Counterclockwise',
        'Coordinate System' => 'Relative',
        'Daylighting Reference Point Coordinate System' => 'Relative',
        'Rectangular Surface Coordinate System' => 'Relative' }.each do |field_name, value|
        field_index = geometry_rules.iddObject.getFieldIndex(field_name)
        geometry_rules.setString(field_index.get, value) if field_index.is_initialized
      end
      workspace.addObject(geometry_rules)
    end

    # The legacy ForwardTranslator adds Output:SQLite when OutputControl:Files requests SQLite output;
    # without it, EnergyPlus writes an empty eplusout.sql.
    def self.add_output_sqlite(workspace)
      sqlite_type = OpenStudio::IddObjectType.new('Output:SQLite')
      return unless workspace.getObjectsByType(sqlite_type).empty?

      control_files = workspace.getObjectsByType(OpenStudio::IddObjectType.new('OutputControl:Files')).first
      return if control_files.nil?

      field_index = control_files.iddObject.getFieldIndex('Output SQLite')
      return unless field_index.is_initialized && control_files.getString(field_index.get).to_s.casecmp('Yes').zero?

      sqlite = OpenStudio::IdfObject.new(sqlite_type)
      sqlite.setString(sqlite.iddObject.getFieldIndex('Option Type').get, 'SimpleAndTabular')
      workspace.addObject(sqlite)
    end

    # The legacy ForwardTranslator adds AllSummary tabular reports and HTML table style by default.
    def self.add_output_table_defaults(workspace)
      summary_type = OpenStudio::IddObjectType.new('Output:Table:SummaryReports')
      if workspace.getObjectsByType(summary_type).empty?
        summary = OpenStudio::IdfObject.new(summary_type)
        summary.setString(0, 'AllSummary')
        workspace.addObject(summary)
      end

      style_type = OpenStudio::IddObjectType.new('OutputControl:Table:Style')
      return unless workspace.getObjectsByType(style_type).empty?

      style = OpenStudio::IdfObject.new(style_type)
      style.setString(style.iddObject.getFieldIndex('Column Separator').get, 'HTML')
      workspace.addObject(style)
    end

    def self.normalize_surface_types(workspace)
      surface_type = OpenStudio::IddObjectType.new('BuildingSurface_Detailed')
      workspace.getObjectsByType(surface_type).each { |surface| normalize_surface_type(surface) }
    end

    # Maps the legacy OpenStudio RoofCeiling surface type to EnergyPlus Roof or Ceiling based on the boundary
    # condition, like the legacy ForwardTranslator. EPModel Roof/Ceiling types (which the Surface#surfaceType shim
    # reports as RoofCeiling) are re-derived the same way.
    def self.normalize_surface_type(surface)
      ground_boundary_conditions = ['Ground', 'GroundFCfactorMethod', 'GroundSlabPreprocessorAverage',
                                    'GroundSlabPreprocessorCore', 'GroundSlabPreprocessorPerimeter',
                                    'GroundBasementPreprocessorAverageWall', 'GroundBasementPreprocessorAverageFloor',
                                    'GroundBasementPreprocessorUpperWall', 'GroundBasementPreprocessorLowerWall', 'Foundation']
      surface_type_index = surface.iddObject.getFieldIndex('Surface Type')
      boundary_condition_index = surface.iddObject.getFieldIndex('Outside Boundary Condition')
      return unless surface_type_index.is_initialized && boundary_condition_index.is_initialized
      return unless ['RoofCeiling', 'Roof', 'Ceiling'].include?(surface.getString(surface_type_index.get).to_s)

      boundary_condition = surface.getString(boundary_condition_index.get).to_s
      is_envelope = boundary_condition.casecmp('Outdoors').zero? || ground_boundary_conditions.include?(boundary_condition)
      surface.setString(surface_type_index.get, is_envelope ? 'Roof' : 'Ceiling')
    end

    def self.normalize_people_temperature_type(workspace)
      people_type = OpenStudio::IddObjectType.new('People')
      workspace.getObjectsByType(people_type).each { |people| normalize_people_temperature(people) }
    end

    # Maps the legacy OpenStudio ZoneAveraged mean radiant temperature type to EnergyPlus EnclosureAveraged.
    def self.normalize_people_temperature(people)
      field_index = people.iddObject.getFieldIndex('Mean Radiant Temperature Calculation Type')
      return unless field_index.is_initialized
      return unless people.getString(field_index.get).to_s == 'ZoneAveraged'

      people.setString(field_index.get, 'EnclosureAveraged')
    end

    def self.declare_ems_output_globals(workspace)
      ems_global_type = OpenStudio::IddObjectType.new('EnergyManagementSystem_GlobalVariable')
      existing_ems_globals = workspace.getObjectsByType(ems_global_type).flat_map do |global_variable|
        global_variable.extensibleGroups.filter_map do |group|
          variable_name = group.getString(0)
          variable_name.get if variable_name.is_initialized
        end
      end
      ems_actuator_type = OpenStudio::IddObjectType.new('EnergyManagementSystem_Actuator')
      existing_ems_variables = existing_ems_globals + workspace.getObjectsByType(ems_actuator_type).filter_map do |actuator|
        name_index = actuator.iddObject.getFieldIndex('Name')
        next unless name_index.is_initialized

        name = actuator.getString(name_index.get)
        name.get if name.is_initialized
      end
      ems_output_type = OpenStudio::IddObjectType.new('EnergyManagementSystem_OutputVariable')
      workspace.getObjectsByType(ems_output_type).each do |output_variable|
        variable_index = output_variable.iddObject.getFieldIndex('EMS Variable Name')
        next unless variable_index.is_initialized

        variable_name = output_variable.getString(variable_index.get)
        next unless variable_name.is_initialized
        next if existing_ems_variables.any? { |existing_name| existing_name.casecmp(variable_name.get).zero? }

        global_variable = OpenStudio::IdfObject.new(ems_global_type)
        group = global_variable.pushExtensibleGroup
        group.setString(0, variable_name.get)
        workspace.addObject(global_variable)
        existing_ems_variables << variable_name.get
      end
    end

    def self.repair_demand_branch_endpoints(workspace)
      plant_loop_type = OpenStudio::IddObjectType.new('PlantLoop')
      branch_list_type = OpenStudio::IddObjectType.new('BranchList')
      branch_type = OpenStudio::IddObjectType.new('Branch')
      pipe_type = OpenStudio::IddObjectType.new('Pipe_Adiabatic')
      workspace.getObjectsByType(plant_loop_type).each do |plant_loop|
        branch_list_index = plant_loop.iddObject.getFieldIndex('Demand Side Branch List Name')
        inlet_node_index = plant_loop.iddObject.getFieldIndex('Demand Side Inlet Node Name')
        outlet_node_index = plant_loop.iddObject.getFieldIndex('Demand Side Outlet Node Name')
        next unless branch_list_index.is_initialized && inlet_node_index.is_initialized && outlet_node_index.is_initialized

        branch_list_name = plant_loop.getString(branch_list_index.get)
        inlet_node_name = plant_loop.getString(inlet_node_index.get)
        outlet_node_name = plant_loop.getString(outlet_node_index.get)
        next unless branch_list_name.is_initialized && inlet_node_name.is_initialized && outlet_node_name.is_initialized

        branch_list = workspace.getObjectByTypeAndName(branch_list_type, branch_list_name.get)
        next unless branch_list.is_initialized

        branch_names = branch_list.get.extensibleGroups.filter_map do |group|
          branch_name = group.getString(0)
          branch_name.get if branch_name.is_initialized
        end
        next if branch_names.length < 2

        loop_name = plant_loop.name.to_s
        [
          [branch_names.first, "#{loop_name} Demand Inlet Pipe", inlet_node_name.get, "#{loop_name} Demand Inlet Pipe Node"],
          [branch_names.last, "#{loop_name} Demand Outlet Pipe", "#{loop_name} Demand Outlet Pipe Node", outlet_node_name.get]
        ].each do |branch_name, pipe_name, pipe_inlet_node_name, pipe_outlet_node_name|
          branch = workspace.getObjectByTypeAndName(branch_type, branch_name)
          next unless branch.is_initialized
          next unless branch.get.numExtensibleGroups == 0

          pipe = OpenStudio::IdfObject.new(pipe_type)
          pipe.setName(pipe_name)
          pipe_inlet_index = pipe.iddObject.getFieldIndex('Inlet Node Name')
          pipe_outlet_index = pipe.iddObject.getFieldIndex('Outlet Node Name')
          next unless pipe_inlet_index.is_initialized && pipe_outlet_index.is_initialized
          next unless pipe.setString(pipe_inlet_index.get, pipe_inlet_node_name)
          next unless pipe.setString(pipe_outlet_index.get, pipe_outlet_node_name)
          next unless workspace.addObject(pipe).is_initialized

          group = branch.get.pushExtensibleGroup
          fields_set = group.setString(0, pipe.iddObject.name.to_s)
          fields_set &&= group.setString(1, pipe_name)
          fields_set &&= group.setString(2, pipe_inlet_node_name)
          fields_set &&= group.setString(3, pipe_outlet_node_name)
          unless fields_set
            branch.get.eraseExtensibleGroup(group.groupIndex)
          end
        end
      end
    end

    def self.plant_branch_component_types(workspace, plant_loop, branch_list_field)
      branch_list_name = plant_loop.getString(plant_loop.iddObject.getFieldIndex(branch_list_field).get)
      return [] unless branch_list_name.is_initialized

      branch_list = workspace.getObjectByTypeAndName('BranchList'.to_IddObjectType, branch_list_name.get).get
      branch_list.extensibleGroups.flat_map do |group|
        branch_name = group.getString(0).get
        branch = workspace.getObjectByTypeAndName('Branch'.to_IddObjectType, branch_name).get
        branch.extensibleGroups.map { |component| component.getString(0).get.downcase }
      end
    end

    def self.normalize_boiler_load_distribution(workspace)
      space_heating_types = ['coil:heating:water', 'zonehvac:baseboard:convective:water']
      workspace.getObjectsByType('PlantLoop'.to_IddObjectType).each do |plant_loop|
        scheme_index = plant_loop.iddObject.getFieldIndex('Load Distribution Scheme').get
        next unless plant_loop.getString(scheme_index, false).to_s.strip.empty?
        next unless plant_branch_component_types(workspace, plant_loop, 'Plant Side Branch List Name').include?('boiler:hotwater')
        next unless plant_branch_component_types(workspace, plant_loop, 'Demand Side Branch List Name').intersect?(space_heating_types)

        unless plant_loop.setString(scheme_index, 'Optimal')
          fail "Could not set the load distribution scheme for '#{plant_loop.name}'."
        end
      end
    end

    def self.add_ground_heat_exchanger_plant_schemes(workspace, model)
      schemes_type = OpenStudio::IddObjectType.new('PlantEquipmentOperationSchemes')
      system_type = OpenStudio::IddObjectType.new('GroundHeatExchanger_System')
      list_type = OpenStudio::IddObjectType.new('PlantEquipmentList')
      operation_type = OpenStudio::IddObjectType.new('PlantEquipmentOperation_Uncontrolled')
      model.getPlantLoops.each do |plant_loop|
        exchangers = plant_loop.supplyComponents.select { |component| component.iddObject.name.to_s == 'GroundHeatExchanger:ResponseFactors' }
        next if exchangers.empty?

        scheme_index = plant_loop.iddObject.getFieldIndex('Plant Equipment Operation Scheme Name')
        raise "Missing operation scheme field on '#{plant_loop.name}'." unless scheme_index.is_initialized

        scheme_name = plant_loop.getString(scheme_index.get)
        raise "Missing operation scheme on '#{plant_loop.name}'." unless scheme_name.is_initialized

        scheme = workspace.getObjectByTypeAndName(schemes_type, scheme_name.get)
        raise "Could not find operation scheme '#{scheme_name.get}'." unless scheme.is_initialized
        next unless scheme.get.numExtensibleGroups == 0

        schedule = workspace.getObjectByTypeAndName('Schedule_Constant'.to_IddObjectType, 'Always On Discrete')
        raise 'Could not find Always On Discrete schedule.' unless schedule.is_initialized

        list = OpenStudio::IdfObject.new(list_type)
        list.setName("#{plant_loop.name} Uncontrolled Equipment List")
        exchangers.each do |exchanger|
          system = workspace.getObjectsByType(system_type).find do |candidate|
            index = candidate.iddObject.getFieldIndex('GHE:Vertical:ResponseFactors Object Name')
            next false unless index.is_initialized

            name = candidate.getString(index.get)
            name.is_initialized && name.get.casecmp(exchanger.name.to_s).zero?
          end
          raise "Could not find system for ground heat exchanger '#{exchanger.name}'." if system.nil?

          group = list.pushExtensibleGroup
          success = group.setString(0, system.iddObject.name.to_s)
          success &&= group.setString(1, system.name.to_s)
          raise "Could not add ground heat exchanger '#{exchanger.name}' to equipment list." unless success
        end
        raise "Could not add equipment list '#{list.name}'." unless workspace.addObject(list).is_initialized

        operation = OpenStudio::IdfObject.new(operation_type)
        operation.setName("#{plant_loop.name} Uncontrolled Operation Scheme")
        list_index = operation.iddObject.getFieldIndex('Equipment List Name')
        raise "Could not set equipment list for '#{operation.name}'." unless list_index.is_initialized && operation.setString(list_index.get, list.name.to_s)
        raise "Could not add operation '#{operation.name}'." unless workspace.addObject(operation).is_initialized

        group = scheme.get.pushExtensibleGroup
        success = group.setString(0, operation.iddObject.name.to_s)
        success &&= group.setString(1, operation.name.to_s)
        success &&= group.setString(2, schedule.get.name.to_s)
        raise "Could not set operation scheme for '#{plant_loop.name}'." unless success
      end
    end

    def self.add_default_heating_plant_schemes(workspace, model)
      operation_scheme_type = OpenStudio::IddObjectType.new('PlantEquipmentOperationSchemes')
      heating_operation_type = OpenStudio::IddObjectType.new('PlantEquipmentOperation_HeatingLoad')
      equipment_list_type = OpenStudio::IddObjectType.new('PlantEquipmentList')
      always_on_schedule_type = OpenStudio::IddObjectType.new('Schedule_Constant')
      always_on_schedule = workspace.getObjectByTypeAndName(always_on_schedule_type, 'Always On Discrete')
      model.getPlantLoops.each do |plant_loop|
        scheme_field_index = plant_loop.iddObject.getFieldIndex('Plant Equipment Operation Scheme Name')
        next unless scheme_field_index.is_initialized

        scheme_name = plant_loop.getString(scheme_field_index.get)
        next unless scheme_name.is_initialized

        scheme = workspace.getObjectByTypeAndName(operation_scheme_type, scheme_name.get)
        next unless scheme.is_initialized

        if scheme.get.numExtensibleGroups != 0
          uncontrolled_name = "#{plant_loop.name} Uncontrolled Operation Scheme"
          has_ground_scheme = scheme.get.extensibleGroups.any? do |group|
            operation_name = group.getString(1)
            operation_name.is_initialized && operation_name.get == uncontrolled_name
          end
          next unless has_ground_scheme
        end

        heating_components = plant_loop.supplyComponents.filter_map do |component|
          component_type = component.iddObject.name.to_s
          next if component_type == 'Node' || component_type.start_with?('Connector:', 'Pump:', 'Pipe:')
          next if component_type == 'GroundHeatExchanger:ResponseFactors'

          hvac_component = component.to_HVACComponent
          next unless hvac_component.is_initialized
          next unless hvac_component.get.componentType.to_s.start_with?('Heating')

          component
        end
        next if heating_components.empty?
        next unless always_on_schedule.is_initialized

        operation_name = "#{plant_loop.name} Heating Operation Scheme"
        equipment_list_name = "#{plant_loop.name} Heating Equipment List"

        equipment_list = OpenStudio::IdfObject.new(equipment_list_type)
        equipment_list.setName(equipment_list_name)
        heating_components.each do |component|
          equipment_group = equipment_list.pushExtensibleGroup
          equipment_group.setString(0, component.iddObject.name.to_s)
          equipment_group.setString(1, component.name.to_s)
        end
        workspace.addObject(equipment_list)

        operation = OpenStudio::IdfObject.new(heating_operation_type)
        operation.setName(operation_name)
        operation_group = operation.pushExtensibleGroup
        operation_group.setDouble(0, 0.0)
        operation_group.setDouble(1, 1.0e9)
        operation_group.setString(2, equipment_list_name)
        workspace.addObject(operation)

        scheme_group = scheme.get.pushExtensibleGroup
        scheme_group.setString(0, operation.iddObject.name.to_s)
        scheme_group.setString(1, operation_name)
        scheme_group.setString(2, always_on_schedule.get.name.to_s)
      end
    end
  end

  unless OpenStudio::EPModel.const_defined?(:InternalMassDefinition, false)
    OpenStudio::EPModel.const_set(:InternalMassDefinition, EPModelCompatibility::InternalMassDefinition)
  end

  unless OpenStudio::EPModel.const_defined?(:InternalMass, false)
    OpenStudio::EPModel.const_set(:InternalMass, EPModelCompatibility::InternalMass)
  end

  unless OpenStudio::EPModel.const_defined?(:OtherEquipmentDefinition, false)
    OpenStudio::EPModel.const_set(:OtherEquipmentDefinition, EPModelCompatibility::OtherEquipmentDefinition)
  end

  unless OpenStudio::EPModel.const_defined?(:ElectricEquipmentDefinition, false)
    OpenStudio::EPModel.const_set(:ElectricEquipmentDefinition, EPModelCompatibility::ElectricEquipmentDefinition)
  end

  unless OpenStudio::EPModel.const_defined?(:WaterUseEquipmentDefinition, false)
    OpenStudio::EPModel.const_set(:WaterUseEquipmentDefinition, EPModelCompatibility::WaterUseEquipmentDefinition)
  end

  unless OpenStudio::EPModel.const_defined?(:LightsDefinition, false)
    OpenStudio::EPModel.const_set(:LightsDefinition, EPModelCompatibility::LightsDefinition)
  end

  unless OpenStudio::EPModel.const_defined?(:PeopleDefinition, false)
    OpenStudio::EPModel.const_set(:PeopleDefinition, EPModelCompatibility::PeopleDefinition)
  end

  unless OpenStudio::EPModel.const_defined?(:OutputMeter, false)
    OpenStudio::EPModel.const_set(:OutputMeter, EPModelCompatibility::OutputMeter)
  end

  native_other_equipment_new = OpenStudio::EPModel::OtherEquipment.method(:new)
  OpenStudio::EPModel::OtherEquipment.define_singleton_method(:new) do |model_or_definition|
    if model_or_definition.is_a?(OpenStudio::EPModel::OtherEquipmentDefinition)
      model_or_definition.equipment
    else
      native_other_equipment_new.call(model_or_definition)
    end
  end

  native_electric_equipment_new = OpenStudio::EPModel::ElectricEquipment.method(:new)
  OpenStudio::EPModel::ElectricEquipment.define_singleton_method(:new) do |model_or_definition|
    if model_or_definition.is_a?(OpenStudio::EPModel::ElectricEquipmentDefinition)
      model_or_definition.equipment
    else
      native_electric_equipment_new.call(model_or_definition)
    end
  end

  native_water_use_equipment_new = OpenStudio::EPModel::WaterUseEquipment.method(:new)
  OpenStudio::EPModel::WaterUseEquipment.define_singleton_method(:new) do |model_or_definition|
    if model_or_definition.is_a?(OpenStudio::EPModel::WaterUseEquipmentDefinition)
      model_or_definition.equipment
    else
      native_water_use_equipment_new.call(model_or_definition)
    end
  end

  native_lights_new = OpenStudio::EPModel::Lights.method(:new)
  OpenStudio::EPModel::Lights.define_singleton_method(:new) do |model_or_definition|
    if model_or_definition.is_a?(OpenStudio::EPModel::LightsDefinition)
      model_or_definition.lights
    else
      native_lights_new.call(model_or_definition)
    end
  end

  native_people_new = OpenStudio::EPModel::People.method(:new)
  OpenStudio::EPModel::People.define_singleton_method(:new) do |model_or_definition|
    if model_or_definition.is_a?(OpenStudio::EPModel::PeopleDefinition)
      model_or_definition.people
    else
      native_people_new.call(model_or_definition)
    end
  end

  native_zone_hvac_four_pipe_fan_coil_new = OpenStudio::EPModel::ZoneHVACFourPipeFanCoil.method(:new)
  OpenStudio::EPModel::ZoneHVACFourPipeFanCoil.define_singleton_method(:new) do |*args|
    if args.length != 5
      return native_zone_hvac_four_pipe_fan_coil_new.call(*args)
    end

    model, availability_schedule, fan, cooling_coil, heating_coil = args
    fan_coil = native_zone_hvac_four_pipe_fan_coil_new.call(model)
    unless fan_coil.setAvailabilitySchedule(availability_schedule) &&
           fan_coil.setSupplyAirFan(fan) &&
           fan_coil.setCoolingCoil(cooling_coil) &&
           fan_coil.setHeatingCoil(heating_coil)
      fan_coil.remove
      raise 'Failed to initialize ZoneHVACFourPipeFanCoil.'
    end

    return fan_coil
  end

  unless OpenStudio::EPModel::OtherEquipment.method_defined?(:setSpace)
    OpenStudio::EPModel::OtherEquipment.define_method(:setSpace) do |space|
      EPModelCompatibility.set_pointer(self, 'Zone or ZoneList or Space or SpaceList Name', space)
    end
  end

  unless OpenStudio::EPModel::OtherEquipment.method_defined?(:setSchedule)
    OpenStudio::EPModel::OtherEquipment.define_method(:setSchedule) do |schedule|
      EPModelCompatibility.set_pointer(self, 'Schedule Name', schedule)
    end
  end

  unless OpenStudio::EPModel::ElectricEquipment.method_defined?(:setSpace)
    OpenStudio::EPModel::ElectricEquipment.define_method(:setSpace) do |space|
      EPModelCompatibility.set_pointer(self, 'Zone or ZoneList or Space or SpaceList Name', space)
    end
  end

  unless OpenStudio::EPModel::ElectricEquipment.method_defined?(:setSchedule)
    OpenStudio::EPModel::ElectricEquipment.define_method(:setSchedule) do |schedule|
      EPModelCompatibility.set_default_schedule_type_limits(schedule, 'Fractional')
      EPModelCompatibility.set_pointer(self, 'Schedule Name', schedule)
    end
  end

  unless OpenStudio::EPModel::WaterUseEquipment.method_defined?(:setFlowRateFractionSchedule)
    OpenStudio::EPModel::WaterUseEquipment.define_method(:setFlowRateFractionSchedule) do |schedule|
      EPModelCompatibility.set_pointer(self, 'Flow Rate Fraction Schedule Name', schedule)
    end
  end

  unless OpenStudio::EPModel::WaterUseEquipment.method_defined?(:flowRateFractionSchedule)
    OpenStudio::EPModel::WaterUseEquipment.define_method(:flowRateFractionSchedule) do
      EPModelCompatibility.get_schedule(self, 'Flow Rate Fraction Schedule Name')
    end
  end

  unless OpenStudio::EPModel::WaterUseEquipment.method_defined?(:targetTemperatureSchedule)
    OpenStudio::EPModel::WaterUseEquipment.define_method(:targetTemperatureSchedule) do
      EPModelCompatibility.get_schedule(self, 'Target Temperature Schedule Name')
    end
  end

  unless OpenStudio::EPModel::WaterUseEquipment.method_defined?(:waterUseEquipmentDefinition)
    OpenStudio::EPModel::WaterUseEquipment.define_method(:waterUseEquipmentDefinition) do
      self
    end
  end

  unless OpenStudio::EPModel::Lights.method_defined?(:setSpace)
    OpenStudio::EPModel::Lights.define_method(:setSpace) do |space|
      EPModelCompatibility.set_pointer(self, 'Zone or ZoneList or Space or SpaceList Name', space)
    end
  end

  unless OpenStudio::EPModel::Lights.method_defined?(:setSchedule)
    OpenStudio::EPModel::Lights.define_method(:setSchedule) do |schedule|
      EPModelCompatibility.set_default_schedule_type_limits(schedule, 'Fractional')
      EPModelCompatibility.set_pointer(self, 'Schedule Name', schedule)
    end
  end

  unless OpenStudio::EPModel::People.method_defined?(:setSpace)
    OpenStudio::EPModel::People.define_method(:setSpace) do |space|
      EPModelCompatibility.set_pointer(self, 'Zone or ZoneList or Space or SpaceList Name', space)
    end
  end

  unless OpenStudio::EPModel::People.method_defined?(:setActivityLevelSchedule)
    OpenStudio::EPModel::People.define_method(:setActivityLevelSchedule) do |schedule|
      EPModelCompatibility.set_default_schedule_type_limits(schedule, 'ActivityLevel')
      EPModelCompatibility.set_pointer(self, 'Activity Level Schedule Name', schedule)
    end
  end

  unless OpenStudio::EPModel::People.method_defined?(:setNumberofPeopleSchedule)
    OpenStudio::EPModel::People.define_method(:setNumberofPeopleSchedule) do |schedule|
      EPModelCompatibility.set_default_schedule_type_limits(schedule, 'Fractional')
      EPModelCompatibility.set_pointer(self, 'Number of People Schedule Name', schedule)
    end
  end

  [OpenStudio::EPModel::Lights, OpenStudio::EPModel::ElectricEquipment, OpenStudio::EPModel::OtherEquipment,
   OpenStudio::EPModel::People, OpenStudio::EPModel::SpaceInfiltrationDesignFlowRate].each do |space_load_class|
    next if space_load_class.method_defined?(:space)

    space_load_class.define_method(:space) do
      field_index = iddObject.getFieldIndex('Zone or ZoneList or Space or SpaceList Name')
      return OpenStudio::EPModel::OptionalSpace.new unless field_index.is_initialized

      target = getTarget(field_index.get)
      return OpenStudio::EPModel::OptionalSpace.new unless target.is_initialized

      target.get.to_Space
    end
  end

  unless OpenStudio::EPModel::SpaceInfiltrationDesignFlowRate.method_defined?(:setSpace)
    OpenStudio::EPModel::SpaceInfiltrationDesignFlowRate.define_method(:setSpace) do |space|
      EPModelCompatibility.set_pointer(self, 'Zone or ZoneList or Space or SpaceList Name', space)
    end
  end

  unless OpenStudio::EPModel::SpaceInfiltrationEffectiveLeakageArea.method_defined?(:setSpace)
    OpenStudio::EPModel::SpaceInfiltrationEffectiveLeakageArea.define_method(:setSpace) do |space|
      EPModelCompatibility.set_pointer(self, 'Zone or Space Name', space)
    end
  end

  unless OpenStudio::EPModel::SpaceInfiltrationEffectiveLeakageArea.method_defined?(:setSchedule)
    OpenStudio::EPModel::SpaceInfiltrationEffectiveLeakageArea.define_method(:setSchedule) do |schedule|
      EPModelCompatibility.set_pointer(self, 'Schedule Name', schedule)
    end
  end

  unless OpenStudio::EPModel::SpaceInfiltrationDesignFlowRate.method_defined?(:setSchedule)
    OpenStudio::EPModel::SpaceInfiltrationDesignFlowRate.define_method(:setSchedule) do |schedule|
      EPModelCompatibility.set_pointer(self, 'Schedule Name', schedule)
    end
  end

  unless OpenStudio::EPModel::Model.method_defined?(:alwaysOffDiscreteSchedule)
    OpenStudio::EPModel::Model.define_method(:alwaysOffDiscreteSchedule) do
      schedule = getScheduleConstantByName('Always Off Discrete')
      if schedule.is_initialized
        raise 'Always Off Discrete schedule must have a value of zero.' unless schedule.get.value == 0.0

        limits = schedule.get.scheduleTypeLimits
        unless limits.is_initialized && limits.get.numericType.is_initialized && limits.get.numericType.get.casecmp('Discrete').zero?
          raise 'Always Off Discrete schedule must have discrete type limits.'
        end

        return schedule.get
      end

      schedule = OpenStudio::EPModel::ScheduleConstant.new(self)
      raise 'Could not name Always Off Discrete schedule.' unless schedule.setName('Always Off Discrete')
      raise 'Could not set Always Off Discrete schedule value.' unless schedule.setValue(0.0)

      limits = alwaysOnDiscreteSchedule.scheduleTypeLimits
      raise 'Could not find discrete schedule type limits.' unless limits.is_initialized
      raise 'Could not set Always Off Discrete schedule type limits.' unless schedule.setScheduleTypeLimits(limits.get)

      return schedule
    end
  end

  native_setpoint_manager_scheduled_new = OpenStudio::EPModel::SetpointManagerScheduled.method(:new)
  OpenStudio::EPModel::SetpointManagerScheduled.define_singleton_method(:new) do |*args|
    if args.length == 2
      setpoint_manager = native_setpoint_manager_scheduled_new.call(args[0])
      unless setpoint_manager.setSchedule(args[1])
        setpoint_manager.remove
        raise 'Unable to set the SetpointManagerScheduled schedule.'
      end
      setpoint_manager
    else
      native_setpoint_manager_scheduled_new.call(*args)
    end
  end

  unless OpenStudio::EPModel.const_defined?(:AirTerminalSingleDuctUncontrolled, false)
    OpenStudio::EPModel.const_set(:AirTerminalSingleDuctUncontrolled, EPModelCompatibility::AirTerminalSingleDuctUncontrolled)
  end

  unless OpenStudio::EPModel::AirLoopHVAC.method_defined?(:multiAddBranchForZone)
    OpenStudio::EPModel::AirLoopHVAC.define_method(:multiAddBranchForZone) do |thermal_zone, air_terminal|
      addBranchForZone(thermal_zone, air_terminal)
    end
  end

  native_ruleset_set_schedule_type_limits = OpenStudio::EPModel::ScheduleRuleset.instance_method(:setScheduleTypeLimits)
  OpenStudio::EPModel::ScheduleRuleset.define_method(:setScheduleTypeLimits) do |limits|
    return false unless native_ruleset_set_schedule_type_limits.bind(self).call(limits)

    days = [defaultDaySchedule, summerDesignDaySchedule, winterDesignDaySchedule, holidaySchedule, customDay1Schedule, customDay2Schedule]
    days.concat(scheduleRules.map(&:daySchedule))
    days.uniq { |day| day.handle.to_s }.each do |day|
      raise "Could not set schedule type limits on '#{day.name}'." unless day.setScheduleTypeLimits(limits)
    end
    true
  end

  native_schedule_rule_new = OpenStudio::EPModel::ScheduleRule.method(:new)
  OpenStudio::EPModel::ScheduleRule.define_singleton_method(:new) do |*args|
    rule = native_schedule_rule_new.call(*args)
    limits = args[0].scheduleTypeLimits
    if limits.is_initialized && !rule.daySchedule.setScheduleTypeLimits(limits.get)
      raise "Could not set schedule type limits on '#{rule.daySchedule.name}'."
    end

    rule
  end

  [:setHeatingSetpointTemperatureSchedule, :setCoolingSetpointTemperatureSchedule].each do |method_name|
    native_setter = OpenStudio::EPModel::ThermostatSetpointDualSetpoint.instance_method(method_name)
    OpenStudio::EPModel::ThermostatSetpointDualSetpoint.define_method(method_name) do |schedule|
      return false unless native_setter.bind(self).call(schedule)

      ruleset = schedule.to_ScheduleRuleset
      if ruleset.is_initialized
        limits = ruleset.get.scheduleTypeLimits
        if limits.is_initialized && !ruleset.get.setScheduleTypeLimits(limits.get)
          raise "Could not set schedule type limits on '#{schedule.name}'."
        end
      end
      true
    end
  end

  unless OpenStudio::EPModel::ThermalZone.method_defined?(:setSequentialHeatingFractionSchedule)
    OpenStudio::EPModel::ThermalZone.define_method(:setSequentialHeatingFractionSchedule) do |equipment, schedule|
      connections = model.getZoneHVACEquipmentConnectionss.find do |connection|
        connection.thermalZone.handle.to_s == handle.to_s
      end
      return false if connections.nil?

      return connections.zoneHVACEquipmentList.setSequentialHeatingFractionSchedule(equipment, schedule)
    end
  end

  unless OpenStudio::EPModel::ThermalZone.method_defined?(:setSequentialCoolingFractionSchedule)
    OpenStudio::EPModel::ThermalZone.define_method(:setSequentialCoolingFractionSchedule) do |equipment, schedule|
      connections = model.getZoneHVACEquipmentConnectionss.find do |connection|
        connection.thermalZone.handle.to_s == handle.to_s
      end
      return false if connections.nil?

      return connections.zoneHVACEquipmentList.setSequentialCoolingFractionSchedule(equipment, schedule)
    end
  end

  unless OpenStudio::EPModel::ThermalZone.method_defined?(:spaces)
    OpenStudio::EPModel::ThermalZone.define_method(:spaces) do
      model.getSpaces.select do |space|
        zone = space.thermalZone
        zone.is_initialized && zone.get.handle.to_s == handle.to_s
      end
    end
  end

  unless OpenStudio::EPModel::ThermalZone.method_defined?(:floorArea)
    OpenStudio::EPModel::ThermalZone.define_method(:floorArea) do
      spaces.sum(&:floorArea)
    end
  end

  unless OpenStudio::EPModel::ThermalZone.method_defined?(:isPlenum)
    OpenStudio::EPModel::ThermalZone.define_method(:isPlenum) do
      return true if model.getAirLoopHVACReturnPlenums.any? do |plenum|
        zone = plenum.thermalZone
        zone.is_initialized && zone.get.handle.to_s == handle.to_s
      end

      model.getAirLoopHVACSupplyPlenums.any? do |plenum|
        zone = plenum.thermalZone
        zone.is_initialized && zone.get.handle.to_s == handle.to_s
      end
    end
  end

  unless OpenStudio::EPModel::Model.method_defined?(:getInternalMassDefinitions)
    OpenStudio::EPModel::Model.define_method(:getInternalMassDefinitions) do
      getInteriorPartitionSurfaces
    end
  end

  # EPModel spaces have no transformation (origin), and Space#setTransformation/changeTransformation return false.
  # Emulate OpenStudio 3.x: keep a virtual transformation per space handle, with surface vertices relative to it.
  # Model.intersectSurfaces/matchSurfaces work in building coordinates, and Model#toIdfFile applies the
  # transformations to the vertices first, as the legacy ForwardTranslator does.
  module EPModelCompatibility
    SpaceTransformations = {}

    def self.space_transformation(space)
      SpaceTransformations[space.handle.to_s] || OpenStudio::Transformation.new
    end

    def self.set_space_transformation(space_or_handle, transformation)
      handle = space_or_handle.respond_to?(:handle) ? space_or_handle.handle.to_s : space_or_handle.to_s
      SpaceTransformations[handle] = transformation
    end

    def self.identity_transformation?(transformation)
      matrix = transformation.matrix
      (0..3).all? { |i| (0..3).all? { |j| (matrix[i, j] - (i == j ? 1.0 : 0.0)).abs < 1e-12 } }
    end

    # Surfaces, subsurfaces, and interior partition surfaces (except area-only internal mass) in the space.
    def self.space_planar_surfaces(space)
      space_handle = space.handle.to_s
      in_space = lambda do |object|
        object_space = object.space
        object_space.is_initialized && object_space.get.handle.to_s == space_handle
      end
      model = space.model
      surfaces = model.getSurfaces.select { |surface| in_space.call(surface) }
      planar_surfaces = surfaces + surfaces.flat_map { |surface| surface.subSurfaces.to_a }
      planar_surfaces += model.getInteriorPartitionSurfaces.select { |surface| in_space.call(surface) }
      planar_surfaces.select { |planar_surface| planar_surface.vertices.size >= 3 }
    end

    def self.transform_space_vertices(space, transformation)
      return true if identity_transformation?(transformation)

      space_planar_surfaces(space).all? { |planar_surface| planar_surface.setVertices(transformation * planar_surface.vertices) }
    end

    def self.apply_space_transformations(model)
      model.getSpaces.each do |space|
        transformation = space_transformation(space)
        next if identity_transformation?(transformation)

        raise "Could not apply transformation to space '#{space.name}'." unless transform_space_vertices(space, transformation)

        set_space_transformation(space, OpenStudio::Transformation.new)
      end
    end
  end

  OpenStudio::EPModel::Space.define_method(:transformation) do
    EPModelCompatibility.space_transformation(self)
  end

  OpenStudio::EPModel::Space.define_method(:setTransformation) do |transformation|
    EPModelCompatibility.set_space_transformation(self, transformation)
    true
  end

  # Keeps building-coordinate geometry unchanged: relative vertices become new_transformation^-1 * old * vertices.
  OpenStudio::EPModel::Space.define_method(:changeTransformation) do |transformation|
    old_transformation = EPModelCompatibility.space_transformation(self)
    return false unless EPModelCompatibility.transform_space_vertices(self, transformation.inverse * old_transformation)

    EPModelCompatibility.set_space_transformation(self, transformation)
    true
  end

  { xOrigin: 0, yOrigin: 1, zOrigin: 2 }.each do |getter, row|
    OpenStudio::EPModel::Space.define_method(getter) do
      EPModelCompatibility.space_transformation(self).matrix[row, 3]
    end

    OpenStudio::EPModel::Space.define_method("set#{getter.to_s[0].upcase}#{getter.to_s[1..]}") do |value|
      matrix = EPModelCompatibility.space_transformation(self).matrix
      new_matrix = OpenStudio::Matrix.new(4, 4, 0)
      (0..3).each { |i| (0..3).each { |j| new_matrix[i, j] = matrix[i, j] } }
      new_matrix[row, 3] = value
      EPModelCompatibility.set_space_transformation(self, OpenStudio::Transformation.new(new_matrix))
      true
    end
  end

  # EPModel defaults new subsurfaces to Window. Like OpenStudio 3.x (SubSurface::defaultSubSurfaceType without a parent
  # surface), default to Skylight for tilts below 60 or at least 179 degrees, otherwise FixedWindow.
  OpenStudio::EPModel::SubSurface.singleton_class.prepend(Module.new do
    def new(*args)
      sub_surface = super
      if (args.size == 2) && args[0].respond_to?(:each) && sub_surface.subSurfaceType.casecmp('Window').zero?
        tilt_deg = sub_surface.tilt * 180.0 / Math::PI
        sub_surface.setSubSurfaceType(((tilt_deg < 60) || (tilt_deg >= 179)) ? 'Skylight' : 'FixedWindow')
      end
      sub_surface
    end
  end)

  # EPModel removes only the object itself; like OpenStudio 3.x, also remove the children: a surface's subsurfaces,
  # and a space's surfaces (with their subsurfaces) and interior partition surfaces.
  native_surface_remove = OpenStudio::EPModel::Surface.instance_method(:remove)
  OpenStudio::EPModel::Surface.define_method(:remove) do
    subSurfaces.each(&:remove)
    native_surface_remove.bind(self).call
  end

  native_space_remove = OpenStudio::EPModel::Space.instance_method(:remove)
  OpenStudio::EPModel::Space.define_method(:remove) do
    space_handle = handle.to_s
    in_space = lambda do |object|
      object_space = object.space
      object_space.is_initialized && object_space.get.handle.to_s == space_handle
    end
    model.getSurfaces.select { |surface| in_space.call(surface) }.each(&:remove)
    model.getInteriorPartitionSurfaces.select { |surface| in_space.call(surface) }.each(&:remove)
    EPModelCompatibility::SpaceTransformations.delete(space_handle)
    native_space_remove.bind(self).call
  end

  # EPModel replaces the legacy OpenStudio RoofCeiling surface type with EnergyPlus Roof and Ceiling. Report both as
  # RoofCeiling and store RoofCeiling as Roof; the IDF export derives Roof or Ceiling from the boundary condition.
  native_surface_type = OpenStudio::EPModel::Surface.instance_method(:surfaceType)
  OpenStudio::EPModel::Surface.define_method(:surfaceType) do
    surface_type = native_surface_type.bind(self).call
    ['Roof', 'Ceiling'].include?(surface_type) ? 'RoofCeiling' : surface_type
  end

  native_set_surface_type = OpenStudio::EPModel::Surface.instance_method(:setSurfaceType)
  OpenStudio::EPModel::Surface.define_method(:setSurfaceType) do |surface_type|
    next native_set_surface_type.bind(self).call(surface_type) unless surface_type.to_s.casecmp('RoofCeiling').zero?
    next true if ['Roof', 'Ceiling'].include?(native_surface_type.bind(self).call)

    native_set_surface_type.bind(self).call('Roof') || native_set_surface_type.bind(self).call('Ceiling')
  end

  # EPModel Space has no SpaceType reference, and EPModel SpaceType objects (IDD SpaceList) are not found by
  # Model#getSpaceType, so keep the SpaceType handle as a process-local feature and the objects by handle.
  unless OpenStudio::EPModel::Space.method_defined?(:setSpaceType)
    EPModelCompatibility.const_set(:SpaceTypesByHandle, {})
    OpenStudio::EPModel::Space.define_method(:setSpaceType) do |space_type|
      EPModelCompatibility::SpaceTypesByHandle[space_type.handle.to_s] = space_type
      EPModelCompatibility::AdditionalProperties.for_object(self).setFeature('EPModelCompatibility:SpaceTypeHandle', space_type.handle.to_s)
    end
  end

  unless OpenStudio::EPModel::Space.method_defined?(:spaceType)
    OpenStudio::EPModel::Space.define_method(:spaceType) do
      space_type_handle = EPModelCompatibility::AdditionalProperties.for_object(self).getFeatureAsString('EPModelCompatibility:SpaceTypeHandle')
      space_type = space_type_handle.is_initialized ? EPModelCompatibility::SpaceTypesByHandle[space_type_handle.get] : nil
      space_type.nil? ? OpenStudio::EPModel::OptionalSpaceType.new : OpenStudio::EPModel::OptionalSpaceType.new(space_type)
    end
  end

  # Port of OpenStudio 3.x Surface::splitSurfaceForSubSurfaces: splits a wall so that each group of overlapping
  # subsurfaces (expanded to full wall height) is on its own surface. Returns the newly created surfaces.
  unless OpenStudio::EPModel::Surface.method_defined?(:splitSurfaceForSubSurfaces)
    OpenStudio::EPModel::Surface.define_method(:splitSurfaceForSubSurfaces) do
      result = []
      expand = 0.0254
      tol = 0.01 # should be less than expand
      next result unless surfaceType.casecmp('Wall').zero?
      next result if adjacentSurface.is_initialized

      sub_surfaces = subSurfaces.to_a
      next result if sub_surfaces.empty?

      transformation = OpenStudio::Transformation.alignFace(vertices)
      inverse_transformation = transformation.inverse
      face_vertices = (inverse_transformation * vertices).to_a.reverse
      next result if face_vertices.size < 3

      ymin = Float::MAX
      ymax = Float::MIN # matches std::numeric_limits<double>::min()
      face_vertices.each do |face_vertex|
        ymin = [ymin, face_vertex.y].min
        ymax = [ymax, face_vertex.y].max
      end
      next result if ymin > ymax

      masks = []
      handle_to_face_vertices = {}
      sub_surfaces.each do |sub_surface|
        sub_surface_face_vertices = (inverse_transformation * sub_surface.vertices).to_a.reverse
        next if sub_surface_face_vertices.size < 3

        handle_to_face_vertices[sub_surface.handle.to_s] = sub_surface_face_vertices
        xmin = Float::MAX
        xmax = Float::MIN
        sub_surface_face_vertices.each do |face_vertex|
          xmin = [xmin, face_vertex.x].min
          xmax = [xmax, face_vertex.x].max
        end
        next if xmin > xmax

        mask = OpenStudio::Point3dVector.new
        [[xmax + expand, ymax + expand], [xmax + expand, ymin - expand],
         [xmin - expand, ymin - expand], [xmin - expand, ymax + expand]].each { |x, y| mask << OpenStudio::Point3d.new(x, y, 0) }
        masks << mask
      end

      new_faces = [face_vertices]
      OpenStudio.joinAll(masks, tol).each do |mask|
        tmp_faces = []
        new_faces.each do |new_face|
          new_face_vector = OpenStudio::Point3dVector.new
          new_face.each { |point| new_face_vector << point }
          intersection = OpenStudio.intersect(new_face_vector, mask, tol)
          if intersection.is_initialized
            tmp_faces << intersection.get.polygon1.to_a
            intersection.get.newPolygons1.each { |polygon| tmp_faces << polygon.to_a }
          else
            tmp_faces << new_face
          end
        end
        new_faces = tmp_faces
      end

      to_vector = lambda do |points|
        vector = OpenStudio::Point3dVector.new
        points.each { |point| vector << point }
        vector
      end
      new_faces = new_faces.sort_by { |new_face| -OpenStudio.getArea(to_vector.call(new_face)).get }

      new_faces.each_with_index do |new_face, i|
        if i == 0
          surface = self # Re-use the original surface
        else
          surface = model.getSurface(EPModelCompatibility.clone_model_object(self, model).handle).get
          EPModelCompatibility::AdditionalProperties.copy_features(self, surface)
          result << surface
        end
        surface.setVertices(transformation * to_vector.call(new_face.reverse))

        handle_to_face_vertices.each do |sub_surface_handle, sub_surface_face_vertices|
          next unless OpenStudio.pointInPolygon(sub_surface_face_vertices[0], to_vector.call(new_face), tol)

          sub_surface = model.getSubSurface(OpenStudio.toUUID(sub_surface_handle))
          sub_surface.get.setSurface(surface) if sub_surface.is_initialized
        end
      end

      result
    end
  end

  # EPModel SpaceType has no standards space type; keep it as a process-local feature.
  unless OpenStudio::EPModel::SpaceType.method_defined?(:setStandardsSpaceType)
    OpenStudio::EPModel::SpaceType.define_method(:setStandardsSpaceType) do |standards_space_type|
      EPModelCompatibility::AdditionalProperties.for_object(self).setFeature('EPModelCompatibility:StandardsSpaceType', standards_space_type.to_s)
    end
  end

  unless OpenStudio::EPModel::SpaceType.method_defined?(:standardsSpaceType)
    OpenStudio::EPModel::SpaceType.define_method(:standardsSpaceType) do
      EPModelCompatibility::AdditionalProperties.for_object(self).getFeatureAsString('EPModelCompatibility:StandardsSpaceType')
    end
  end

  # EPModel Space inherits IdfObject#clone, which copies only the Space object and does not add it to the model.
  # Like OpenStudio 3.x, clone the space with its surfaces and subsurfaces (adjacent-surface references are not
  # remapped), plus process-local additionalProperties features and the virtual transformation.
  OpenStudio::EPModel::Space.define_method(:clone) do |target_model = model|
    new_space = target_model.getSpace(EPModelCompatibility.clone_model_object(self, target_model).handle).get
    EPModelCompatibility::AdditionalProperties.copy_features(self, new_space)
    EPModelCompatibility.set_space_transformation(new_space, EPModelCompatibility.space_transformation(self))
    surfaces.each do |surface|
      new_surface = target_model.getSurface(EPModelCompatibility.clone_model_object(surface, target_model).handle).get
      raise "Could not assign cloned surface '#{new_surface.name}' to space '#{new_space.name}'." unless new_surface.setSpace(new_space)

      EPModelCompatibility::AdditionalProperties.copy_features(surface, new_surface)
      surface.subSurfaces.each do |sub_surface|
        new_sub_surface = target_model.getSubSurface(EPModelCompatibility.clone_model_object(sub_surface, target_model).handle).get
        raise "Could not assign cloned subsurface '#{new_sub_surface.name}'." unless new_sub_surface.setSurface(new_surface)

        EPModelCompatibility::AdditionalProperties.copy_features(sub_surface, new_sub_surface)
      end
    end
    new_space
  end

  [:intersectSurfaces, :matchSurfaces].each do |function_name|
    native_function = OpenStudio::EPModel.method(function_name)
    OpenStudio::EPModel.define_singleton_method(function_name) do |spaces, *args|
      transformations = spaces.map { |space| [space, EPModelCompatibility.space_transformation(space)] }
      transformations.each { |space, transformation| EPModelCompatibility.transform_space_vertices(space, transformation) }
      result = native_function.call(spaces, *args)
      transformations.each { |space, transformation| EPModelCompatibility.transform_space_vertices(space, transformation.inverse) }
      result
    end
  end

  native_to_idf_file = OpenStudio::EPModel::Model.instance_method(:toIdfFile)
  OpenStudio::EPModel::Model.define_method(:toIdfFile) do |*args|
    EPModelCompatibility.apply_space_transformations(self)
    native_to_idf_file.bind(self).call(*args)
  end

  # EPModel actuators store the actuated component's name as text, so renaming the component (e.g., in
  # prefix_object_names) breaks the reference. Record the component handle to refresh the name later.
  EPModelCompatibility.const_set(:ActuatedComponentHandles, {})
  OpenStudio::EPModel::EnergyManagementSystemActuator.singleton_class.prepend(Module.new do
    def new(*args)
      actuator = super
      component = args.first
      if component.respond_to?(:handle) && component.respond_to?(:iddObject)
        EPModelCompatibility::ActuatedComponentHandles[actuator.handle.to_s] = component.handle.to_s
      end
      actuator
    end
  end)

  # EPModel setters accept legacy OpenStudio values (RoofCeiling surfaces, ZoneAveraged People) that addObjects
  # rejects against the EnergyPlus IDD, so map them first (e.g., when merge_unit_models combines unit models).
  # Also refresh actuated component names, and carry the process-local additionalProperties features over
  # to the copies, which get new handles.
  native_add_objects = OpenStudio::EPModel::Model.instance_method(:addObjects)
  OpenStudio::EPModel::Model.define_method(:addObjects) do |objects, *args|
    objects.each do |object|
      case object.iddObject.name
      when 'BuildingSurface:Detailed' then EPModelCompatibility.normalize_surface_type(object)
      when 'People' then EPModelCompatibility.normalize_people_temperature(object)
      when 'EnergyManagementSystem:Actuator'
        component_handle = EPModelCompatibility::ActuatedComponentHandles[object.handle.to_s]
        next if component_handle.nil?

        component = object.workspace.getObject(OpenStudio.toUUID(component_handle))
        next unless component.is_initialized

        object.setString(object.iddObject.getFieldIndex('Actuated Component Unique Name').get, component.get.nameString)
      end
    end
    added_objects = native_add_objects.bind(self).call(objects, *args)
    if added_objects.size == objects.size
      objects.zip(added_objects) do |from, to|
        EPModelCompatibility::AdditionalProperties.copy_features(from, to)
        transformation = EPModelCompatibility::SpaceTransformations[from.handle.to_s]
        EPModelCompatibility.set_space_transformation(to, transformation) unless transformation.nil?
      end
    end
    added_objects
  end

  # Like OpenStudio 3.x, return ZoneMixing objects that use this zone as either the receiving or source zone.
  unless OpenStudio::EPModel::ThermalZone.method_defined?(:zoneMixing)
    OpenStudio::EPModel::ThermalZone.define_method(:zoneMixing) do
      zone_handle = handle.to_s
      model.getZoneMixings.select do |zone_mixing|
        ['Zone or Space Name', 'Source Zone or Space Name'].any? do |field_name|
          field_index = zone_mixing.iddObject.getFieldIndex(field_name)
          next false unless field_index.is_initialized

          target = zone_mixing.getTarget(field_index.get)
          target.is_initialized && target.get.handle.to_s == zone_handle
        end
      end
    end
  end

  # EPModel InteriorPartitionSurface objects are exported as EnergyPlus InternalMass objects.
  unless OpenStudio::EPModel::Model.method_defined?(:getInternalMasss)
    OpenStudio::EPModel::Model.define_method(:getInternalMasss) do
      getInteriorPartitionSurfaces
    end
  end

  unless OpenStudio::EPModel::Model.method_defined?(:getModelObjects)
    OpenStudio::EPModel::Model.define_method(:getModelObjects) do
      objects
    end
  end

  unless OpenStudio::EPModel::Model.method_defined?(:getOutputMeters)
    OpenStudio::EPModel::Model.define_method(:getOutputMeters) do
      meter_type = OpenStudio::IddObjectType.new('Output_Meter')
      getObjectsByType(meter_type).map { |object| EPModelCompatibility::OutputMeter.new(object) }
    end
  end

  # EPModel models have no workflow. Keep a WorkflowJSON on the Ruby model wrapper so callers can
  # register file search paths; ScheduleFile.new below resolves relative file names against them.
  unless OpenStudio::EPModel::Model.method_defined?(:workflowJSON)
    OpenStudio::EPModel::Model.define_method(:workflowJSON) do
      @workflow_json ||= OpenStudio::WorkflowJSON.new
    end
  end

  # EPModel's ScheduleFile constructor requires a path it can find directly. Like OpenStudio 3.x,
  # resolve a relative file name against the model's workflow file paths first, then restore the
  # relative name so the IDF references it relative to the run directory.
  OpenStudio::EPModel::ScheduleFile.singleton_class.prepend(Module.new do
    def new(model, file_path, *args)
      relative_path = nil
      if (not File.absolute_path?(file_path.to_s)) && model.respond_to?(:workflowJSON)
        found_path = model.workflowJSON.findFile(file_path.to_s)
        if found_path.is_initialized
          relative_path = file_path.to_s
          file_path = found_path.get.to_s
        end
      end
      schedule_file = super(model, file_path, *args)
      if (not relative_path.nil?) && (not schedule_file.setFileName(relative_path))
        raise "Could not set relative file name '#{relative_path}' on ScheduleFile."
      end

      schedule_file
    end
  end)

  [:heater1SetpointTemperatureSchedule, :heater2SetpointTemperatureSchedule].each do |method_name|
    native_getter = OpenStudio::EPModel::WaterHeaterStratified.instance_method(method_name)
    OpenStudio::EPModel::WaterHeaterStratified.define_method(method_name) do
      native_getter.bind(self).call.get
    end
  end

  native_wrapped_hpwh_new = OpenStudio::EPModel::WaterHeaterHeatPumpWrappedCondenser.method(:new)
  OpenStudio::EPModel::WaterHeaterHeatPumpWrappedCondenser.define_singleton_method(:new) do |*args|
    if args.length != 6
      return native_wrapped_hpwh_new.call(*args)
    end

    model, coil, tank, fan, setpoint_schedule, availability_schedule = args
    # Avoid creating the model-only constructor's default components.
    idf_object = OpenStudio::IdfObject.new('WaterHeater:HeatPump:WrappedCondenser'.to_IddObjectType)
    hpwh = model.addObject(idf_object).get.to_WaterHeaterHeatPumpWrappedCondenser.get
    unless hpwh.setInletAirConfiguration('Schedule') &&
           hpwh.setDXCoil(coil) &&
           hpwh.setTank(tank) &&
           hpwh.setFan(fan) &&
           hpwh.setCompressorSetpointTemperatureSchedule(setpoint_schedule) &&
           hpwh.setAvailabilitySchedule(availability_schedule)
      hpwh.remove
      raise 'Failed to initialize WaterHeaterHeatPumpWrappedCondenser.'
    end

    return hpwh
  end

  # Native speeds materializes transient SpeedData objects and can crash.
  # Read the fields used by HPXML directly from the coil's ordered IDF groups.
  { OpenStudio::EPModel::CoilHeatingWaterToAirHeatPumpVariableSpeedEquationFit => 'Heating',
    OpenStudio::EPModel::CoilCoolingWaterToAirHeatPumpVariableSpeedEquationFit => 'Cooling' }.each do |coil_class, mode|
    coil_class.define_method(:speeds) do
      fields = iddObject.extensibleGroup.map(&:name).each_with_index.to_h
      extensibleGroups.map { |group| EPModelCompatibility::WaterToAirHeatPumpSpeed.new(group, fields, mode) }
    end
  end

  native_fan_add_speed = OpenStudio::EPModel::FanSystemModel.instance_method(:addSpeed)
  OpenStudio::EPModel::FanSystemModel.define_method(:addSpeed) do |*args|
    return false unless native_fan_add_speed.bind(self).call(*args)

    # Native addSpeed writes the speed groups but does not update the count.
    field_index = iddObject.getFieldIndex('Number of Speeds').get
    raise "Could not set the number of speeds for fan '#{name}'." unless setInt(field_index, numExtensibleGroups)

    true
  end

  OpenStudio::EPModel::FanSystemModel.define_method(:numberofSpeeds) do
    field_index = iddObject.getFieldIndex('Number of Speeds')
    return 1 unless field_index.is_initialized

    speed_count = getInt(field_index.get)
    speed_count.is_initialized ? speed_count.get : 1
  end

  unless OpenStudio::EPModel::OutputTableMonthly.method_defined?(:numberofMonthlyVariableGroups)
    OpenStudio::EPModel::OutputTableMonthly.define_method(:numberofMonthlyVariableGroups) do
      numExtensibleGroups
    end
  end

  unless OpenStudio::EPModel::OutputTableMonthly.method_defined?(:getMonthlyVariableGroup)
    OpenStudio::EPModel::OutputTableMonthly.define_method(:getMonthlyVariableGroup) do |index|
      groups = extensibleGroups
      group = nil
      if index >= 0 && index < groups.length
        group = EPModelCompatibility::MonthlyVariableGroup.new(groups[index])
      end
      EPModelCompatibility::OptionalMonthlyVariableGroup.new(group)
    end
  end

  unless OpenStudio::EPModel::OutputTableMonthly.method_defined?(:addMonthlyVariableGroup)
    OpenStudio::EPModel::OutputTableMonthly.define_method(:addMonthlyVariableGroup) do |variable_or_meter_name, aggregation_type|
      group = pushExtensibleGroup
      fields_set = group.setString(0, variable_or_meter_name)
      fields_set &&= group.setString(1, aggregation_type)

      if not fields_set
        eraseExtensibleGroup(group.groupIndex)
        return false
      end

      return true
    end
  end

  unless OpenStudio::EPModel::Model.method_defined?(:getShadingSurfaceGroups)
    OpenStudio::EPModel::Model.define_method(:getShadingSurfaceGroups) do
      group_type = OpenStudio::IddObjectType.new('OS_ShadingSurfaceGroup')
      getObjectsByType(group_type).map { |group| EPModelCompatibility::ShadingSurfaceGroup.new(self, group) }
    end
  end

  native_surface_property_convection_coefficients_new = OpenStudio::EPModel::SurfacePropertyConvectionCoefficients.method(:new)
  OpenStudio::EPModel::SurfacePropertyConvectionCoefficients.define_singleton_method(:new) do |model_or_surface|
    if model_or_surface.is_a?(OpenStudio::EPModel::Surface)
      property = native_surface_property_convection_coefficients_new.call(model_or_surface.model)
      field_index = property.iddObject.getFieldIndex('Surface Name')
      unless field_index.is_initialized && property.setPointer(field_index.get, model_or_surface.handle)
        property.remove
        raise 'Unable to associate SurfacePropertyConvectionCoefficients with the Surface.'
      end
      property
    else
      native_surface_property_convection_coefficients_new.call(model_or_surface)
    end
  end

  native_zone_mixing_new = OpenStudio::EPModel::ZoneMixing.method(:new)
  OpenStudio::EPModel::ZoneMixing.define_singleton_method(:new) do |model_or_zone|
    if model_or_zone.is_a?(OpenStudio::EPModel::Model)
      native_zone_mixing_new.call(model_or_zone)
    else
      zone_mixing = native_zone_mixing_new.call(model_or_zone.model)
      field_index = zone_mixing.iddObject.getFieldIndex('Zone or Space Name')
      unless field_index.is_initialized && zone_mixing.setPointer(field_index.get, model_or_zone.handle)
        zone_mixing.remove
        raise 'Unable to associate ZoneMixing with the destination zone or space.'
      end
      zone_mixing
    end
  end

  unless OpenStudio::EPModel::ZoneMixing.method_defined?(:setSourceZone)
    OpenStudio::EPModel::ZoneMixing.define_method(:setSourceZone) do |zone|
      field_index = iddObject.getFieldIndex('Source Zone or Space Name')
      field_index.is_initialized && setPointer(field_index.get, zone.handle)
    end
  end

  unless OpenStudio::EPModel::SubSurface.method_defined?(:shadingSurfaceGroups)
    OpenStudio::EPModel::SubSurface.define_method(:shadingSurfaceGroups) do
      model.getShadingSurfaceGroups.select { |group| group.shadesSubSurface?(self) }
    end
  end

  if not OpenStudio::WorkspaceObject.method_defined?(:additionalProperties)
    OpenStudio::WorkspaceObject.define_method(:additionalProperties) do
      EPModelCompatibility::AdditionalProperties.for_object(self)
    end
  end

  if not OpenStudio::EPModel::ModelObject.method_defined?(:additionalProperties)
    OpenStudio::EPModel::ModelObject.define_method(:additionalProperties) do
      EPModelCompatibility::AdditionalProperties.for_object(self)
    end
  end

  if OpenStudio::EPModel::SubSurfaceVector.method_defined?(:to_a)
    if not OpenStudio::EPModel::SubSurfaceVector.method_defined?(:to_ary)
      OpenStudio::EPModel::SubSurfaceVector.define_method(:to_ary) do
        to_a
      end
    end
  end

  unless OpenStudio::EPModel::FoundationKiva.method_defined?(:setExteriorHorizontalInsulationMaterial)
    OpenStudio::EPModel::FoundationKiva.define_method(:setExteriorHorizontalInsulationMaterial) do |material|
      EPModelCompatibility.set_pointer(self, 'Exterior Horizontal Insulation Material Name', material)
    end
  end

  unless OpenStudio::EPModel::FoundationKiva.method_defined?(:setExteriorVerticalInsulationMaterial)
    OpenStudio::EPModel::FoundationKiva.define_method(:setExteriorVerticalInsulationMaterial) do |material|
      EPModelCompatibility.set_pointer(self, 'Exterior Vertical Insulation Material Name', material)
    end
  end

  unless OpenStudio::EPModel::FoundationKiva.method_defined?(:setInteriorHorizontalInsulationMaterial)
    OpenStudio::EPModel::FoundationKiva.define_method(:setInteriorHorizontalInsulationMaterial) do |material|
      EPModelCompatibility.set_pointer(self, 'Interior Horizontal Insulation Material Name', material)
    end
  end

  unless OpenStudio::EPModel::FoundationKiva.method_defined?(:setInteriorVerticalInsulationMaterial)
    OpenStudio::EPModel::FoundationKiva.define_method(:setInteriorVerticalInsulationMaterial) do |material|
      EPModelCompatibility.set_pointer(self, 'Interior Vertical Insulation Material Name', material)
    end
  end

  OpenStudio::EPModel::ZoneHVACDehumidifierDX.define_method(:setAvailabilitySchedule) do |schedule|
    EPModelCompatibility.set_pointer(self, 'Availability Schedule Name', schedule)
  end

  OpenStudio::EPModel::WaterUseConnections.define_method(:waterUseEquipment) do
    EPModelCompatibility.get_water_use_equipments(self)
  end

  OpenStudio::EPModel::Model.define_method(:getBoilerHotWaters) do
    EPModelCompatibility.get_boiler_hot_waters(self)
  end

  OpenStudio::EPModel::Model.define_method(:getElectricLoadCenterDistributions) do
    getObjectsByType('ElectricLoadCenter:Distribution'.to_IddObjectType).map do |object|
      object.to_ElectricLoadCenterDistribution.get
    end
  end

  [OpenStudio::EPModel::WaterHeaterMixed, OpenStudio::EPModel::WaterHeaterStratified].each do |tank_class|
    native_add_to_node = tank_class.instance_method(:addToNode)
    tank_class.define_method(:addToNode) do |node|
      detached = EPModelCompatibility.detach_water_heater_branch_for_move(self, node)
      added = native_add_to_node.bind(self).call(node)
      fail "Could not reattach '#{name}' after removing its original supply branch." if detached && !added

      added
    end
  end

  unless OpenStudio::EPModel::CoilWaterHeatingDesuperheater.method_defined?(:addToHeatRejectionTarget)
    OpenStudio::EPModel::CoilWaterHeatingDesuperheater.define_method(:addToHeatRejectionTarget) do |tank|
      tank_type = tank.iddObject.name.to_s
      unless ['WaterHeater:Mixed', 'WaterHeater:Stratified'].include?(tank_type)
        raise ArgumentError, "Unsupported desuperheater tank type '#{tank_type}'."
      end

      inlet = OpenStudio::EPModel::Node.new(model)
      outlet = OpenStudio::EPModel::Node.new(model)
      unless EPModelCompatibility.set_pointer(self, 'Tank Name', tank) &&
             setString(iddObject.getFieldIndex('Tank Object Type').get, tank_type) &&
             EPModelCompatibility.set_pointer(self, 'Water Inlet Node Name', inlet) &&
             EPModelCompatibility.set_pointer(self, 'Water Outlet Node Name', outlet) &&
             EPModelCompatibility.set_pointer(tank, 'Source Side Inlet Node Name', outlet) &&
             EPModelCompatibility.set_pointer(tank, 'Source Side Outlet Node Name', inlet)
        raise "Could not connect desuperheater '#{name}' to tank '#{tank.name}'."
      end

      true
    end
  end

  native_desuperheater_set_heating_source = OpenStudio::EPModel::CoilWaterHeatingDesuperheater.instance_method(:setHeatingSource)
  OpenStudio::EPModel::CoilWaterHeatingDesuperheater.define_method(:setHeatingSource) do |coil|
    unless native_desuperheater_set_heating_source.bind(self).call(coil) &&
           setString(iddObject.getFieldIndex('Heating Source Object Type').get, coil.iddObject.name.to_s)
      raise "Could not set the heating source for desuperheater '#{name}'."
    end

    true
  end

  { getCoilCoolingDXSingleSpeeds: ['Coil:Cooling:DX:SingleSpeed', :to_CoilCoolingDXSingleSpeed],
    getCoilCoolingDXMultiSpeeds: ['Coil:Cooling:DX:MultiSpeed', :to_CoilCoolingDXMultiSpeed],
    getCoilCoolingWaterToAirHeatPumpEquationFits: ['Coil:Cooling:WaterToAirHeatPump:EquationFit', :to_CoilCoolingWaterToAirHeatPumpEquationFit],
    getCoilCoolingWaterToAirHeatPumpVariableSpeedEquationFits: ['Coil:Cooling:WaterToAirHeatPump:VariableSpeedEquationFit', :to_CoilCoolingWaterToAirHeatPumpVariableSpeedEquationFit] }.each do |method_name, (idd_type, cast)|
    OpenStudio::EPModel::Model.define_method(method_name) do
      getObjectsByType(idd_type.to_IddObjectType).map { |object| object.public_send(cast).get }
    end
  end

  native_generator_pv_watts_new = OpenStudio::EPModel::GeneratorPVWatts.method(:new)
  OpenStudio::EPModel::GeneratorPVWatts.define_singleton_method(:new) do |*args|
    if args.length != 2
      return native_generator_pv_watts_new.call(*args)
    end

    model, capacity = args
    generator = native_generator_pv_watts_new.call(model)
    unless generator.setDCSystemCapacity(capacity)
      generator.remove
      raise 'Failed to set GeneratorPVWatts DC system capacity.'
    end

    return generator
  end

  { setElectricalPowerFunctionofTemperatureandElevationCurve: 'Electrical Power Function of Temperature and Elevation Curve Name',
    setElectricalEfficiencyFunctionofTemperatureCurve: 'Electrical Efficiency Function of Temperature Curve Name',
    setElectricalEfficiencyFunctionofPartLoadRatioCurve: 'Electrical Efficiency Function of Part Load Ratio Curve Name' }.each do |method_name, field_name|
    next if OpenStudio::EPModel::GeneratorMicroTurbine.method_defined?(method_name)

    OpenStudio::EPModel::GeneratorMicroTurbine.define_method(method_name) do |curve|
      raise "Could not set #{field_name} for '#{name}'." unless EPModelCompatibility.set_pointer(self, field_name, curve)

      true
    end
  end

  { inverter: 'Inverter Name', electricalStorage: 'Electrical Storage Object Name' }.each do |method_name, field_name|
    next if OpenStudio::EPModel::ElectricLoadCenterDistribution.method_defined?(method_name)

    OpenStudio::EPModel::ElectricLoadCenterDistribution.define_method(method_name) do
      getTarget(iddObject.getFieldIndex(field_name).get)
    end
  end

  unless OpenStudio::EPModel::ElectricLoadCenterDistribution.method_defined?(:setInverter)
    OpenStudio::EPModel::ElectricLoadCenterDistribution.define_method(:setInverter) do |inverter|
      raise "Could not attach inverter to '#{name}'." unless EPModelCompatibility.set_pointer(self, 'Inverter Name', inverter)

      # Direct IDF export does not infer a DC bus from the inverter.
      if isElectricalBussTypeDefaulted && !setElectricalBussType('DirectCurrentWithInverter')
        raise "Could not set the electrical bus type for '#{name}'."
      end

      true
    end
  end

  unless OpenStudio::EPModel::ElectricLoadCenterDistribution.method_defined?(:setElectricalStorage)
    OpenStudio::EPModel::ElectricLoadCenterDistribution.define_method(:setElectricalStorage) do |storage|
      raise "Could not attach electrical storage to '#{name}'." unless EPModelCompatibility.set_pointer(self, 'Electrical Storage Object Name', storage)

      true
    end
  end

  unless OpenStudio::EPModel::ElectricLoadCenterDistribution.method_defined?(:generators)
    OpenStudio::EPModel::ElectricLoadCenterDistribution.define_method(:generators) do
      list = getTarget(iddObject.getFieldIndex('Generator List Name').get)
      next [] unless list.is_initialized

      list.get.extensibleGroups.map do |group|
        group.to_WorkspaceExtensibleGroup.get.getTarget(0).get
      end
    end
  end

  unless OpenStudio::EPModel::ElectricLoadCenterDistribution.method_defined?(:addGenerator)
    OpenStudio::EPModel::ElectricLoadCenterDistribution.define_method(:addGenerator) do |generator|
      case generator
      when OpenStudio::EPModel::GeneratorMicroTurbine
        rated_power = generator.referenceElectricalPowerOutput
      when OpenStudio::EPModel::GeneratorPVWatts
        rated_power = generator.dcSystemCapacity
      else
        raise ArgumentError, 'The EPModel addGenerator shim supports only microturbines and PVWatts generators.'
      end

      if isGeneratorOperationSchemeTypeDefaulted && !setGeneratorOperationSchemeType('Baseload')
        raise "Could not set the generator operation scheme for '#{name}'."
      end

      list_index = iddObject.getFieldIndex('Generator List Name').get
      list = getTarget(list_index)
      if list.is_initialized
        generator_list = list.get
      else
        idf_object = OpenStudio::IdfObject.new('ElectricLoadCenter:Generators'.to_IddObjectType)
        idf_object.setName("#{name} Generators")
        generator_list = model.addObject(idf_object).get
        unless setPointer(list_index, generator_list.handle)
          generator_list.remove
          raise "Could not attach a generator list to '#{name}'."
        end
      end

      group = generator_list.pushExtensibleGroup.to_WorkspaceExtensibleGroup.get
      unless group.setPointer(0, generator.handle) &&
             group.setString(1, generator.iddObject.name.to_s) &&
             group.setDouble(2, rated_power)
        generator_list.eraseExtensibleGroup(group.groupIndex)
        raise "Could not add generator '#{generator.name}' to '#{name}'."
      end

      true
    end
  end

  if not OpenStudio::EPModel::FoundationKiva.method_defined?(:addCustomBlock)
    OpenStudio::EPModel::FoundationKiva.define_method(:addCustomBlock) do |material, depth, x_position, z_position|
      if numExtensibleGroups >= 10
        return false
      end

      group = pushExtensibleGroup
      fields_set = group.setString(0, material.name.to_s)
      fields_set &&= group.setDouble(1, depth)
      fields_set &&= group.setDouble(2, x_position)
      fields_set &&= group.setDouble(3, z_position)

      if not fields_set
        eraseExtensibleGroup(group.groupIndex)
        return false
      end

      return true
    end
  end

  if not OpenStudio::EPModel::EnergyManagementSystemProgram.method_defined?(:addLine)
    OpenStudio::EPModel::EnergyManagementSystemProgram.define_method(:addLine) do |line|
      program_line, *comments = line.delete("\r\n").split('!', -1)
      group = pushExtensibleGroup
      line_set = group.setString(0, program_line.to_s.strip.delete(','))

      if not line_set
        eraseExtensibleGroup(group.groupIndex)
        return false
      end

      group.setFieldComment(0, comments.join(', ')) unless comments.empty?
      return true
    end
  end

  OpenStudio::EPModel::EnergyManagementSystemGlobalVariable.define_method(:name) do
    group = extensibleGroups.first
    next '' if group.nil?

    variable_name = group.getString(0)
    variable_name.is_initialized ? variable_name.get : ''
  end

  OpenStudio::EPModel::EnergyManagementSystemGlobalVariable.define_method(:setName) do |new_name|
    group = extensibleGroups.first || pushExtensibleGroup
    next OpenStudio::OptionalString.new unless group.setString(0, new_name.to_s)

    OpenStudio::OptionalString.new(new_name.to_s)
  end

  # Model#objects returns untyped WorkspaceObjects, which bypass the GlobalVariable name/setName shims
  # (e.g., when prefix_object_names renames unit model objects), so return the typed objects instead.
  native_objects = OpenStudio::EPModel::Model.instance_method(:objects)
  OpenStudio::EPModel::Model.define_method(:objects) do |*args|
    global_variables = getEnergyManagementSystemGlobalVariables.to_h { |global_variable| [global_variable.handle.to_s, global_variable] }
    native_objects.bind(self).call(*args).map { |object| global_variables.fetch(object.handle.to_s, object) }
  end

  [OpenStudio::EPModel::MeterCustom, OpenStudio::EPModel::MeterCustomDecrement].each do |meter_class|
    unless meter_class.method_defined?(:keyVarGroups)
      meter_class.define_method(:keyVarGroups) do
        extensibleGroups.map { |group| [group.getString(0).to_s, group.getString(1).to_s] }
      end
    end

    unless meter_class.method_defined?(:removeAllKeyVarGroups)
      meter_class.define_method(:removeAllKeyVarGroups) do
        clearExtensibleGroups
      end
    end

    next if meter_class.method_defined?(:addKeyVarGroup)

    meter_class.define_method(:addKeyVarGroup) do |key, output_variable_or_meter|
      group = pushExtensibleGroup
      fields_set = group.setString(0, key)
      fields_set &&= group.setString(1, output_variable_or_meter)

      if not fields_set
        eraseExtensibleGroup(group.groupIndex)
        return false
      end

      return true
    end
  end

  # EPModel's PlanarSurface#netArea returns the gross area for surfaces; subtract subsurfaces like OpenStudio 3.x.
  OpenStudio::EPModel::Surface.define_method(:netArea) do
    subSurfaces.inject(grossArea) { |area, sub_surface| area - sub_surface.multiplier * sub_surface.grossArea }
  end

  unless OpenStudio::EPModel::OutputDiagnostics.method_defined?(:addKey)
    OpenStudio::EPModel::OutputDiagnostics.define_method(:addKey) do |key|
      existing_keys = extensibleGroups.map { |group| group.getString(0) }.select(&:is_initialized).map(&:get)
      return true if existing_keys.any? { |existing_key| existing_key.casecmp(key).zero? }

      group = pushExtensibleGroup
      if not group.setString(0, key)
        eraseExtensibleGroup(group.groupIndex)
        return false
      end

      return true
    end
  end

  if not OpenStudio::EPModel::EnergyManagementSystemSubroutine.method_defined?(:addLine)
    OpenStudio::EPModel::EnergyManagementSystemSubroutine.define_method(:addLine) do |line|
      program_line, *comments = line.delete("\r\n").split('!', -1)
      group = pushExtensibleGroup
      line_set = group.setString(0, program_line.to_s.strip.delete(','))

      if not line_set
        eraseExtensibleGroup(group.groupIndex)
        return false
      end

      group.setFieldComment(0, comments.join(', ')) unless comments.empty?
      return true
    end
  end

  # Like OpenStudio 3.x, lines are returned newline-terminated (with any field comment) and setLines replaces them.
  [OpenStudio::EPModel::EnergyManagementSystemProgram, OpenStudio::EPModel::EnergyManagementSystemSubroutine].each do |program_class|
    unless program_class.method_defined?(:lines)
      program_class.define_method(:lines) do
        extensibleGroups.map do |group|
          comment = group.fieldComment(0).to_s
          "#{group.getString(0)}#{comment.empty? ? '' : " #{comment}"}\n"
        end
      end
    end

    next if program_class.method_defined?(:setLines)

    program_class.define_method(:setLines) do |lines|
      clearExtensibleGroups
      lines.all? { |line| addLine(line) }
    end
  end

  # EPModel returns the sensor key name as an OptionalString; OpenStudio 3.x returns a String.
  OpenStudio::EPModel::EnergyManagementSystemSensor.define_method(:keyName) do
    getString(iddObject.getFieldIndex('Output:Variable or Output:Meter Index Key Name').get).to_s
  end

  # EPModel EMS output variables reference EMS variables by name only.
  unless OpenStudio::EPModel::EnergyManagementSystemOutputVariable.method_defined?(:emsVariableObject)
    OpenStudio::EPModel::EnergyManagementSystemOutputVariable.define_method(:emsVariableObject) do
      OpenStudio::EPModel::OptionalModelObject.new
    end
  end

  if not OpenStudio::EPModel::EnergyManagementSystemOutputVariable.method_defined?(:setEMSProgramOrSubroutineName)
    OpenStudio::EPModel::EnergyManagementSystemOutputVariable.define_method(:setEMSProgramOrSubroutineName) do |program_or_subroutine|
      field_index = iddObject.getFieldIndex('EMS Program or Subroutine Name')
      if not field_index.is_initialized
        return false
      end

      return setPointer(field_index.get, program_or_subroutine.handle)
    end
  end

  if not OpenStudio::EPModel::Surface.method_defined?(:setAdjacentFoundation)
    OpenStudio::EPModel::Surface.define_method(:setAdjacentFoundation) do |foundation|
      field_index = iddObject.getFieldIndex('Outside Boundary Condition Object')
      if not field_index.is_initialized
        return false
      end

      if not setPointer(field_index.get, foundation.handle)
        return false
      end

      return setOutsideBoundaryCondition('Foundation')
    end
  end

  OpenStudio::EPModel::Surface.define_method(:setSurfacePropertyOtherSideCoefficients) do |other_side_coefficients|
    unless EPModelCompatibility.set_pointer(self, 'Outside Boundary Condition Object', other_side_coefficients)
      return false
    end

    field_index = iddObject.getFieldIndex('Outside Boundary Condition')
    return false unless field_index.is_initialized

    setString(field_index.get, 'OtherSideCoefficients')
  end

  if not OpenStudio::EPModel::Surface.method_defined?(:adjacentFoundation)
    OpenStudio::EPModel::Surface.define_method(:adjacentFoundation) do
      field_index = iddObject.getFieldIndex('Outside Boundary Condition Object')
      if not field_index.is_initialized
        return OpenStudio::EPModel::OptionalFoundationKiva.new
      end

      target = getTarget(field_index.get)
      if not target.is_initialized
        return OpenStudio::EPModel::OptionalFoundationKiva.new
      end

      target_handle = target.get.handle.to_s
      foundation = model.getFoundationKivas.find { |kiva| kiva.handle.to_s == target_handle }
      if foundation.nil?
        return OpenStudio::EPModel::OptionalFoundationKiva.new
      end

      return OpenStudio::EPModel::OptionalFoundationKiva.new(foundation)
    end
  end

  if not OpenStudio::EPModel::Surface.method_defined?(:createSurfacePropertyExposedFoundationPerimeter)
    OpenStudio::EPModel::Surface.define_method(:createSurfacePropertyExposedFoundationPerimeter) do |calculation_method, exposed_perimeter|
      optional_property = OpenStudio::EPModel::OptionalSurfacePropertyExposedFoundationPerimeter
      existing_property = model.getSurfacePropertyExposedFoundationPerimeters.find do |property|
        field_index = property.iddObject.getFieldIndex('Surface Name')
        next false unless field_index.is_initialized

        target = property.getTarget(field_index.get)
        target.is_initialized && target.get.handle.to_s == handle.to_s
      end
      if not existing_property.nil?
        return optional_property.new
      end

      property = OpenStudio::EPModel::SurfacePropertyExposedFoundationPerimeter.new(model)
      field_index = property.iddObject.getFieldIndex('Surface Name')
      if not field_index.is_initialized
        property.remove
        return optional_property.new
      end

      fields_set = property.setPointer(field_index.get, handle)
      fields_set &&= property.setExposedPerimeterCalculationMethod(calculation_method)
      if calculation_method == 'TotalExposedPerimeter'
        fields_set &&= property.setTotalExposedPerimeter(exposed_perimeter)
      elsif calculation_method == 'ExposedPerimeterFraction'
        fields_set &&= property.setExposedPerimeterFraction(exposed_perimeter)
      end

      if not fields_set
        property.remove
        return optional_property.new
      end

      return optional_property.new(property)
    end
  end

  incident_solar_multiplier_class = OpenStudio::EPModel::SurfacePropertyIncidentSolarMultiplier
  if not incident_solar_multiplier_class.method_defined?(:setSubSurface)
    incident_solar_multiplier_class.define_method(:setSubSurface) do |subsurface|
      field_index = iddObject.getFieldIndex('Surface Name')
      if not field_index.is_initialized
        return false
      end

      return setPointer(field_index.get, subsurface.handle)
    end

    incident_solar_multiplier_class.define_method(:setIncidentSolarMultiplierSchedule) do |schedule|
      field_index = iddObject.getFieldIndex('Incident Solar Multiplier Schedule Name')
      if not field_index.is_initialized
        return false
      end

      return setPointer(field_index.get, schedule.handle)
    end

    native_constructor = incident_solar_multiplier_class.method(:new)
    incident_solar_multiplier_class.define_singleton_method(:new) do |model_or_subsurface|
      if not model_or_subsurface.is_a?(OpenStudio::EPModel::SubSurface)
        return native_constructor.call(model_or_subsurface)
      end

      subsurface = model_or_subsurface
      subsurface_type = subsurface.subSurfaceType
      unless ['FixedWindow', 'OperableWindow', 'Skylight'].include?(subsurface_type)
        raise ArgumentError, "SurfacePropertyIncidentSolarMultiplier does not support subsurface type '#{subsurface_type}'."
      end

      property = native_constructor.call(subsurface.model)
      if not property.setSubSurface(subsurface)
        property.remove
        raise 'Failed to associate SurfacePropertyIncidentSolarMultiplier with its subsurface.'
      end

      if not property.setIncidentSolarMultiplier(1.0)
        property.remove
        raise 'Failed to set the default incident solar multiplier.'
      end

      return property
    end
  end

  unless OpenStudio::EPModel::SurfacePropertyOtherSideCoefficients.method_defined?(:setConstantTemperatureSchedule)
    OpenStudio::EPModel::SurfacePropertyOtherSideCoefficients.define_method(:setConstantTemperatureSchedule) do |schedule|
      EPModelCompatibility.set_pointer(self, 'Constant Temperature Schedule Name', schedule)
    end
  end

  { OpenStudio::EPModel::SiteGroundTemperatureShallow => 'SurfaceGroundTemperature',
    OpenStudio::EPModel::SiteGroundTemperatureDeep => 'DeepGroundTemperature' }.each do |ground_temperature_class, field_suffix|
    if not ground_temperature_class.method_defined?(:resetAllMonths)
      ground_temperature_class.define_method(:resetAllMonths) do
        Date::MONTHNAMES[1..12].each do |month|
          public_send("reset#{month}#{field_suffix}")
        end
        nil
      end
    end

    next unless not ground_temperature_class.method_defined?(:setAllMonthlyTemperatures)

    ground_temperature_class.define_method(:setAllMonthlyTemperatures) do |temperatures|
      if temperatures.size != 12
        return false
      end

      Date::MONTHNAMES[1..12].each_with_index do |month, index|
        public_send("set#{month}#{field_suffix}", temperatures[index])
      end
      true
    end
  end

  # GroundHeatExchangerVertical compatibility shims for methods not exposed by EPModel
  # These are methods from OpenStudio 3.11 SDK that EPModel doesn't directly expose.
  # Note: groundTemperature and maximumLengthofSimulation have no direct EnergyPlus fields
  # and need special handling.

  native_ground_heat_exchanger_vertical_new = OpenStudio::EPModel::GroundHeatExchangerVertical.method(:new)
  OpenStudio::EPModel::GroundHeatExchangerVertical.define_singleton_method(:new) do |*args|
    exchanger = native_ground_heat_exchanger_vertical_new.call(*args)
    properties_index = exchanger.iddObject.getFieldIndex('GHE:Vertical:Properties Object Name')
    raise 'Ground heat exchanger properties field is missing.' unless properties_index.is_initialized

    properties = exchanger.getTarget(properties_index.get)
    raise 'Ground heat exchanger properties are missing.' unless properties.is_initialized

    { 'Grout Thermal Heat Capacity' => 3.90e6, 'Pipe Thermal Heat Capacity' => 1.77e6 }.each do |field_name, value|
      index = properties.get.iddObject.getFieldIndex(field_name)
      raise "Missing ground heat exchanger #{field_name} field." unless index.is_initialized
      next if properties.get.getDouble(index.get).is_initialized

      raise "Could not set ground heat exchanger #{field_name}." unless properties.get.setDouble(index.get, value)
    end
    exchanger
  end

  OpenStudio::EPModel::PlantLoop.define_method(:setGlycolFluidType) do |glycol_type, concentration|
    raise ArgumentError, 'Glycol concentration must be an integer between 0 and 100.' unless concentration.is_a?(Integer) && concentration.between?(0, 100)

    raise "Unsupported glycol type '#{glycol_type}'." unless ['PropyleneGlycol', 'EthyleneGlycol'].include?(glycol_type)

    fluid_name = "#{glycol_type}_#{concentration}"
    [
      ['FluidProperties_GlycolConcentration', { 'Name' => fluid_name, 'Glycol Type' => glycol_type, 'Glycol Concentration' => concentration * 0.01 }],
      ['FluidProperties_Name', { 'Fluid Name' => fluid_name, 'Fluid Type' => 'Glycol' }]
    ].each do |type, fields|
      idd_type = OpenStudio::IddObjectType.new(type)
      existing = model.getObjectsByType(idd_type).find { |object| object.name.to_s.casecmp(fluid_name).zero? }
      next unless existing.nil?

      object = OpenStudio::IdfObject.new(idd_type)
      fields.each do |field_name, value|
        index = object.iddObject.getFieldIndex(field_name)
        raise "Missing #{type} field '#{field_name}'." unless index.is_initialized

        success = value.is_a?(Numeric) ? object.setDouble(index.get, value) : object.setString(index.get, value)
        raise "Could not set #{type} field '#{field_name}'." unless success
      end
      raise "Could not add #{type} '#{fluid_name}'." unless model.addObject(object).is_initialized
    end

    fluid_type_index = iddObject.getFieldIndex('Fluid Type')
    user_fluid_index = iddObject.getFieldIndex('User Defined Fluid Type')
    success = fluid_type_index.is_initialized && user_fluid_index.is_initialized
    success &&= setString(fluid_type_index.get, 'UserDefinedFluidType')
    success &&= setString(user_fluid_index.get, fluid_name)
    raise "Could not set user-defined glycol on PlantLoop '#{name}'." unless success

    true
  end

  native_follow_ground_add_to_node = OpenStudio::EPModel::SetpointManagerFollowGroundTemperature.instance_method(:addToNode)
  OpenStudio::EPModel::SetpointManagerFollowGroundTemperature.define_method(:addToNode) do |node|
    return true if native_follow_ground_add_to_node.bind(self).call(node)

    plant_loop = node.plantLoop
    return false unless plant_loop.is_initialized && node.model == model
    return false unless plant_loop.get.supplyOutletNode.handle == node.handle

    EPModelCompatibility.set_pointer(self, 'Setpoint Node or NodeList Name', node)
  end

  unless OpenStudio::EPModel::GroundHeatExchangerVertical.method_defined?(:setGroundTemperature)
    OpenStudio::EPModel::GroundHeatExchangerVertical.define_method(:setGroundTemperature) do |temperature|
      # Set temperature on the undisturbed ground temperature model
      begin
        xing = undisturbedGroundTemperatureModel.to_SiteGroundTemperatureUndisturbedXing
        if xing.is_initialized
          xing.get.setAverageSoilSurfaceTemperature(temperature)
          return true
        end
      rescue StandardError
        # If to_SiteGroundTemperatureUndisturbedXing fails, this isn't an Xing model
      end
      false
    end
  end

  unless OpenStudio::EPModel::GroundHeatExchangerVertical.method_defined?(:groundTemperature)
    OpenStudio::EPModel::GroundHeatExchangerVertical.define_method(:groundTemperature) do
      # Get temperature from the undisturbed ground temperature model
      begin
        xing = undisturbedGroundTemperatureModel.to_SiteGroundTemperatureUndisturbedXing
        if xing.is_initialized
          return OpenStudio::OptionalDouble.new(xing.get.averageSoilSurfaceTemperature)
        end
      rescue StandardError
        # If to_SiteGroundTemperatureUndisturbedXing fails, this isn't an Xing model
      end
      OpenStudio::OptionalDouble.new
    end
  end

  unless OpenStudio::EPModel::GroundHeatExchangerVertical.method_defined?(:setMaximumLengthofSimulation)
    OpenStudio::EPModel::GroundHeatExchangerVertical.define_method(:setMaximumLengthofSimulation) do |_value|
      # maximumLengthofSimulation has no direct EnergyPlus field
      # This is a known limitation of EPModel - just silently succeed
      true
    end
  end

  unless OpenStudio::EPModel::GroundHeatExchangerVertical.method_defined?(:maximumLengthofSimulation)
    OpenStudio::EPModel::GroundHeatExchangerVertical.define_method(:maximumLengthofSimulation) do
      # maximumLengthofSimulation has no direct EnergyPlus field - return default
      OpenStudio::OptionalInt.new(1)
    end
  end
end
