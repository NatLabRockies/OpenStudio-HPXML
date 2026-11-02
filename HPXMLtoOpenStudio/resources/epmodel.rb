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

    class AdditionalProperties
      def self.for_object(object)
        @features_by_handle ||= {}
        return new(@features_by_handle[object.handle.to_s] ||= {})
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

      def shadesSubSurface?(subsurface)
        field_index = @object.iddObject.getFieldIndex('Shaded Object Name')
        return false unless field_index.is_initialized

        target = @object.getTarget(field_index.get)
        target.is_initialized && target.get.handle.to_s == subsurface.handle.to_s
      end
    end

    class AirTerminalSingleDuctUncontrolled
      def self.new(model, schedule)
        terminal = OpenStudio::EPModel::AirTerminalSingleDuctVAVNoReheat.new(model, schedule)
        terminal.setConstantMinimumAirFlowFraction(0.0)
        terminal.setFixedMinimumAirFlowRate(0.0)
        return terminal
      end
    end

    def self.normalize_workspace(workspace, model)
      add_global_geometry_rules(workspace)
      normalize_surface_types(workspace)
      normalize_people_temperature_type(workspace)
      declare_ems_output_globals(workspace)
      repair_demand_branch_endpoints(workspace)
      add_default_heating_plant_schemes(workspace, model)
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

    def self.normalize_surface_types(workspace)
      ground_boundary_conditions = ['Ground', 'GroundFCfactorMethod', 'GroundSlabPreprocessorAverage',
                                    'GroundSlabPreprocessorCore', 'GroundSlabPreprocessorPerimeter',
                                    'GroundBasementPreprocessorAverageWall', 'GroundBasementPreprocessorAverageFloor',
                                    'GroundBasementPreprocessorUpperWall', 'GroundBasementPreprocessorLowerWall', 'Foundation']
      surface_type = OpenStudio::IddObjectType.new('BuildingSurface_Detailed')
      workspace.getObjectsByType(surface_type).each do |surface|
        surface_type_index = surface.iddObject.getFieldIndex('Surface Type')
        boundary_condition_index = surface.iddObject.getFieldIndex('Outside Boundary Condition')
        next unless surface_type_index.is_initialized && boundary_condition_index.is_initialized
        next unless surface.getString(surface_type_index.get).get == 'RoofCeiling'

        boundary_condition = surface.getString(boundary_condition_index.get).get
        is_envelope = boundary_condition.casecmp('Outdoors').zero? || ground_boundary_conditions.include?(boundary_condition)
        surface.setString(surface_type_index.get, is_envelope ? 'Roof' : 'Ceiling')
      end
    end

    def self.normalize_people_temperature_type(workspace)
      people_type = OpenStudio::IddObjectType.new('People')
      workspace.getObjectsByType(people_type).each do |people|
        field_index = people.iddObject.getFieldIndex('Mean Radiant Temperature Calculation Type')
        next unless field_index.is_initialized
        next unless people.getString(field_index.get).get == 'ZoneAveraged'

        people.setString(field_index.get, 'EnclosureAveraged')
      end
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
        next unless scheme.get.numExtensibleGroups == 0

        heating_components = plant_loop.supplyComponents.filter_map do |component|
          component_type = component.iddObject.name.to_s
          next if component_type == 'Node' || component_type.start_with?('Connector:', 'Pump:', 'Pipe:')

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
      EPModelCompatibility.set_pointer(self, 'Schedule Name', schedule)
    end
  end

  unless OpenStudio::EPModel::WaterUseEquipment.method_defined?(:setFlowRateFractionSchedule)
    OpenStudio::EPModel::WaterUseEquipment.define_method(:setFlowRateFractionSchedule) do |schedule|
      EPModelCompatibility.set_pointer(self, 'Flow Rate Fraction Schedule Name', schedule)
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
      EPModelCompatibility.set_pointer(self, 'Activity Level Schedule Name', schedule)
    end
  end

  unless OpenStudio::EPModel::People.method_defined?(:setNumberofPeopleSchedule)
    OpenStudio::EPModel::People.define_method(:setNumberofPeopleSchedule) do |schedule|
      EPModelCompatibility.set_pointer(self, 'Number of People Schedule Name', schedule)
    end
  end

  [OpenStudio::EPModel::Lights, OpenStudio::EPModel::ElectricEquipment, OpenStudio::EPModel::OtherEquipment].each do |space_load_class|
    unless space_load_class.method_defined?(:space)
      space_load_class.define_method(:space) do
        field_index = iddObject.getFieldIndex('Zone or ZoneList or Space or SpaceList Name')
        return OpenStudio::EPModel::OptionalSpace.new unless field_index.is_initialized

        target = getTarget(field_index.get)
        return OpenStudio::EPModel::OptionalSpace.new unless target.is_initialized

        target.get.to_Space
      end
    end
  end

  unless OpenStudio::EPModel::SpaceInfiltrationDesignFlowRate.method_defined?(:setSpace)
    OpenStudio::EPModel::SpaceInfiltrationDesignFlowRate.define_method(:setSpace) do |space|
      EPModelCompatibility.set_pointer(self, 'Zone or ZoneList or Space or SpaceList Name', space)
    end
  end

  unless OpenStudio::EPModel::SpaceInfiltrationDesignFlowRate.method_defined?(:setSchedule)
    OpenStudio::EPModel::SpaceInfiltrationDesignFlowRate.define_method(:setSchedule) do |schedule|
      EPModelCompatibility.set_pointer(self, 'Schedule Name', schedule)
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
      group = if index >= 0 && index < groups.length
                EPModelCompatibility::MonthlyVariableGroup.new(groups[index])
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

  unless OpenStudio::EPModel::MeterCustom.method_defined?(:addKeyVarGroup)
    OpenStudio::EPModel::MeterCustom.define_method(:addKeyVarGroup) do |key, output_variable_or_meter|
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

    if not ground_temperature_class.method_defined?(:setAllMonthlyTemperatures)
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
  end

  # GroundHeatExchangerVertical compatibility shims for methods not exposed by EPModel
  # These are methods from OpenStudio 3.11 SDK that EPModel doesn't directly expose.
  # Note: groundTemperature and maximumLengthofSimulation have no direct EnergyPlus fields
  # and need special handling.

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