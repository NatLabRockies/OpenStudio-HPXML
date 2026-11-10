require_relative '../resources/minitest_helper'
require 'openstudio'
require_relative '../measure.rb'

class HPXMLtoOpenStudioEPModelTest < Minitest::Test
  def test_additional_properties
    model = OpenStudio::Model::Model.new
    zone = OpenStudio::Model::ThermalZone.new(model)
    properties = zone.additionalProperties
    getters = [:getFeatureAsString, :getFeatureAsInteger, :getFeatureAsDouble, :getFeatureAsBoolean]
    getters.each do |getter|
      assert(properties.public_send(getter, 'missing').empty?)
    end

    object_type = 'conditioned space'
    assert(properties.setFeature('ObjectType', object_type))
    object_type.replace('changed after assignment')
    assert(properties.setFeature('BuildingID', 'Building1'))
    assert(properties.setFeature('Integer', 3))
    assert(properties.setFeature('Double', 3.5))
    assert(properties.setFeature('Boolean', false))
    retrieved = model.getThermalZones[0].additionalProperties
    assert_equal('conditioned space', retrieved.getFeatureAsString('ObjectType').get)
    assert_equal('Building1', retrieved.getFeatureAsString('BuildingID').get)
    assert_equal(3, retrieved.getFeatureAsInteger('Integer').get)
    assert_equal(3.5, retrieved.getFeatureAsDouble('Double').get)
    assert(retrieved.getFeatureAsBoolean('Boolean').is_initialized)
    assert_equal(false, retrieved.getFeatureAsBoolean('Boolean').get)
    assert(retrieved.getFeatureAsInteger('ObjectType').empty?)
    assert(retrieved.getFeatureAsString('Integer').empty?)
    assert(retrieved.getFeatureAsDouble('Integer').empty?)
    assert(retrieved.getFeatureAsInteger('Double').empty?)
    assert(retrieved.getFeatureAsBoolean('Integer').empty?)

    properties.setFeature('Integer', 4.5)
    assert(retrieved.getFeatureAsInteger('Integer').empty?)
    assert_equal(4.5, retrieved.getFeatureAsDouble('Integer').get)
    properties.setFeature('Boolean', true)
    assert_equal(true, retrieved.getFeatureAsBoolean('Boolean').get)
    zone.setName('Renamed Zone')
    assert_equal('Building1', model.getThermalZones[0].additionalProperties.getFeatureAsString('BuildingID').get)

    other_zone = OpenStudio::Model::ThermalZone.new(model)
    assert(other_zone.additionalProperties.getFeatureAsString('ObjectType').empty?)
    other_model = OpenStudio::Model::Model.new
    other_model_zone = OpenStudio::Model::ThermalZone.new(other_model)
    assert(other_model_zone.additionalProperties.getFeatureAsString('ObjectType').empty?)
    site = model.getSite
    site.additionalProperties.setFeature('ObjectType', 'site')
    assert_equal('site', model.getSite.additionalProperties.getFeatureAsString('ObjectType').get)
    assert_equal('conditioned space', retrieved.getFeatureAsString('ObjectType').get)
  end

  def test_ground_temperature_bulk_helpers
    model = OpenStudio::Model::Model.new
    [[model.getSiteGroundTemperatureShallow, 'SurfaceGroundTemperature'],
     [model.getSiteGroundTemperatureDeep, 'DeepGroundTemperature']].each do |ground, field_suffix|
      assert(ground.setAllMonthlyTemperatures([10.0] * 12))
      assert_equal(false, ground.setAllMonthlyTemperatures([20.0] * 11))
      assert_equal(false, ground.setAllMonthlyTemperatures([20.0] * 13))
      Date::MONTHNAMES[1..12].each do |month|
        assert_in_delta(10.0, ground.public_send("#{month.downcase}#{field_suffix}"), 0.0001)
      end

      ground.resetAllMonths

      Date::MONTHNAMES[1..12].each do |month|
        assert(ground.public_send("is#{month}#{field_suffix}Defaulted"))
      end
    end
  end

  def test_model_namespace
    if Version::UseEPModel
      assert_same(OpenStudio::EPModel, OpenStudio::Model)
      assert_same(OpenStudio::EPModel::Model, OpenStudio::Model::Model)
    else
      assert_equal('OpenStudio::Model', OpenStudio::Model.name)
    end
  end

  def test_schedule_type_limits_propagation
    return unless Version::UseEPModel

    model = OpenStudio::Model::Model.new
    ruleset = Model.add_schedule_ruleset(model, name: 'Test Ruleset', limits: EPlus::ScheduleTypeLimitsTemperature)
    limits = ruleset.scheduleTypeLimits.get
    assert_equal(limits.handle, ruleset.defaultDaySchedule.scheduleTypeLimits.get.handle)
    rule = OpenStudio::Model::ScheduleRule.new(ruleset)
    assert_equal(limits.handle, rule.daySchedule.scheduleTypeLimits.get.handle)

    replacement = OpenStudio::Model::ScheduleTypeLimits.new(model)
    replacement.setName('Replacement Limits')
    assert(ruleset.setScheduleTypeLimits(replacement))
    assert_equal(replacement.handle, rule.daySchedule.scheduleTypeLimits.get.handle)

    thermostat = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(model)
    [:setHeatingSetpointTemperatureSchedule, :setCoolingSetpointTemperatureSchedule].each do |setter|
      setpoint = Model.add_schedule_ruleset(model, name: setter.to_s)
      setpoint_rule = OpenStudio::Model::ScheduleRule.new(setpoint)
      assert(thermostat.public_send(setter, setpoint))
      inferred_limits = setpoint.scheduleTypeLimits.get
      assert_equal('Temperature', inferred_limits.unitType)
      assert_equal(inferred_limits.handle, setpoint_rule.daySchedule.scheduleTypeLimits.get.handle)
    end

    fractional = Model.add_schedule_constant(model, name: 'Equipment Schedule', value: 0.5)
    equipment = OpenStudio::Model::ElectricEquipment.new(OpenStudio::Model::ElectricEquipmentDefinition.new(model))
    assert(equipment.setSchedule(fractional))
    assert_equal('Fractional', fractional.scheduleTypeLimits.get.name.to_s)
    assert_equal(0, fractional.scheduleTypeLimits.get.lowerLimitValue.get)
    assert_equal(1, fractional.scheduleTypeLimits.get.upperLimitValue.get)

    activity = Model.add_schedule_constant(model, name: 'Activity Schedule', value: 100.0)
    people = OpenStudio::Model::People.new(OpenStudio::Model::PeopleDefinition.new(model))
    assert(people.setActivityLevelSchedule(activity))
    assert_equal('ActivityLevel', activity.scheduleTypeLimits.get.name.to_s)
    assert_equal('ActivityLevel', activity.scheduleTypeLimits.get.unitType)
    assert_equal(0, activity.scheduleTypeLimits.get.lowerLimitValue.get)

    custom = OpenStudio::Model::ScheduleTypeLimits.new(model)
    custom.setName('Custom Limits')
    assert(activity.setScheduleTypeLimits(custom))
    assert(people.setActivityLevelSchedule(activity))
    assert_equal(custom.handle, activity.scheduleTypeLimits.get.handle)
  end

  def test_ground_heat_exchanger_and_glycol
    return unless Version::UseEPModel

    model = OpenStudio::Model::Model.new
    plant_loop = OpenStudio::Model::PlantLoop.new(model)
    plant_loop.setName('Test Condenser Loop')
    assert(plant_loop.setGlycolFluidType('PropyleneGlycol', 20))
    exchanger = OpenStudio::Model::GroundHeatExchangerVertical.new(model)
    properties_index = exchanger.iddObject.getFieldIndex('GHE:Vertical:Properties Object Name').get
    properties = exchanger.getTarget(properties_index).get

    workspace = OpenStudio::Workspace.new(model.toIdfFile)
    grout_heat_capacity_index = properties.iddObject.getFieldIndex('Grout Thermal Heat Capacity').get
    pipe_heat_capacity_index = properties.iddObject.getFieldIndex('Pipe Thermal Heat Capacity').get
    assert_in_delta(3.90e6, properties.getDouble(grout_heat_capacity_index).get, 0.1)
    assert_in_delta(1.77e6, properties.getDouble(pipe_heat_capacity_index).get, 0.1)

    idf_plant_loop = workspace.getObjectByTypeAndName('PlantLoop'.to_IddObjectType, 'Test Condenser Loop').get
    fluid_type_index = idf_plant_loop.iddObject.getFieldIndex('Fluid Type').get
    user_fluid_index = idf_plant_loop.iddObject.getFieldIndex('User Defined Fluid Type').get
    assert_equal('UserDefinedFluidType', idf_plant_loop.getString(fluid_type_index).get)
    assert_equal('PropyleneGlycol_20', idf_plant_loop.getString(user_fluid_index).get)

    glycol = workspace.getObjectByTypeAndName('FluidProperties_GlycolConcentration'.to_IddObjectType, 'PropyleneGlycol_20').get
    concentration_index = glycol.iddObject.getFieldIndex('Glycol Concentration').get
    assert_in_delta(0.2, glycol.getDouble(concentration_index).get, 0.0001)
    fluid = workspace.getObjectByTypeAndName('FluidProperties_Name'.to_IddObjectType, 'PropyleneGlycol_20').get
    fluid_type_index = fluid.iddObject.getFieldIndex('Fluid Type').get
    assert_equal('Glycol', fluid.getString(fluid_type_index).get)

    other_loop = OpenStudio::Model::PlantLoop.new(model)
    assert(other_loop.setGlycolFluidType('PropyleneGlycol', 20))
    assert_equal(1, model.getObjectsByType('FluidProperties_GlycolConcentration'.to_IddObjectType).size)
    assert_equal(1, model.getObjectsByType('FluidProperties_Name'.to_IddObjectType).size)
    assert_raises(ArgumentError) { other_loop.setGlycolFluidType('PropyleneGlycol', 101) }
  end

  def test_ground_heat_exchanger_uncontrolled_operation
    return unless Version::UseEPModel

    model = OpenStudio::Model::Model.new
    plant_loop = OpenStudio::Model::PlantLoop.new(model)
    plant_loop.setName('Ground Loop')
    exchanger = OpenStudio::Model::GroundHeatExchangerVertical.new(model)
    exchanger.setName('Ground Exchanger')
    assert(plant_loop.addSupplyBranchForComponent(exchanger))
    model.alwaysOnDiscreteSchedule
    workspace = OpenStudio::Workspace.new(model.toIdfFile)
    EPModelCompatibility.add_ground_heat_exchanger_plant_schemes(workspace, model)
    EPModelCompatibility.add_default_heating_plant_schemes(workspace, model)

    list = workspace.getObjectByTypeAndName('PlantEquipmentList'.to_IddObjectType, 'Ground Loop Uncontrolled Equipment List').get
    group = list.extensibleGroups[0]
    assert_equal('GroundHeatExchanger:System', group.getString(0).get)
    system_name = group.getString(1).get
    system = workspace.getObjectByTypeAndName('GroundHeatExchanger_System'.to_IddObjectType, system_name).get
    index = system.iddObject.getFieldIndex('GHE:Vertical:ResponseFactors Object Name').get
    assert_equal('Ground Exchanger', system.getString(index).get)
    assert(workspace.getObjectByTypeAndName('PlantEquipmentOperation_Uncontrolled'.to_IddObjectType, 'Ground Loop Uncontrolled Operation Scheme').is_initialized)
    assert(workspace.getObjectByTypeAndName('PlantEquipmentList'.to_IddObjectType, 'Ground Loop Heating Equipment List').empty?)
  end

  def test_follow_ground_temperature_setpoint_node
    return unless Version::UseEPModel

    model = OpenStudio::Model::Model.new
    plant_loop = OpenStudio::Model::PlantLoop.new(model)
    manager = OpenStudio::Model::SetpointManagerFollowGroundTemperature.new(model)
    assert(manager.addToNode(plant_loop.supplyOutletNode))
    index = manager.iddObject.getFieldIndex('Setpoint Node or NodeList Name').get
    assert_equal(plant_loop.supplyOutletNode.handle, manager.getTarget(index).get.handle)
  end

  def test_space_and_zone_constructors
    model = OpenStudio::Model::Model.new
    thermal_zone = OpenStudio::Model::ThermalZone.new(model)
    space = OpenStudio::Model::Space.new(model)
    thermal_zone.setName('Test Zone')
    thermal_zone.setMultiplier(3)
    space.setName('Test Space')

    assert(space.setThermalZone(thermal_zone))
    assert_equal(thermal_zone.handle, space.thermalZone.get.handle)
    assert_equal('Test Zone', thermal_zone.name.to_s)
    assert_equal('Test Space', space.name.to_s)
    assert_equal(3, thermal_zone.multiplier)
    assert_equal(1, model.getThermalZones.size)
    assert_equal(1, model.getSpaces.size)
    if Version::UseEPModel
      assert_instance_of(OpenStudio::EPModel::ThermalZone, thermal_zone)
      assert_instance_of(OpenStudio::EPModel::Space, space)
    end
  end

  def test_apply_year_run_period
    weather = Struct.new(:header).new(Struct.new(:NumRecords).new(8784))
    [[2007, 1, 1, 12, 31, 2007, 'Monday'],
     [2010, 6, 1, 9, 30, 2010, 'Tuesday'],
     [2012, 2, 29, 12, 31, 2012, 'Wednesday'],
     [2010, 10, 1, 3, 31, 2011, 'Friday']].each do |year, begin_month, begin_day, end_month, end_day, end_year, weekday|
      model = OpenStudio::Model::Model.new
      header = HPXML.new.header
      header.sim_calendar_year = year
      header.sim_begin_month = begin_month
      header.sim_begin_day = begin_day
      header.sim_end_month = end_month
      header.sim_end_day = end_day
      run_period = model.getRunPeriod
      run_period.setBeginMonth(begin_month)
      run_period.setBeginDayOfMonth(begin_day)
      run_period.setEndMonth(end_month)
      run_period.setEndDayOfMonth(end_day)

      Location.apply_year(model, header, weather)

      if not Version::UseEPModel
        workspace = OpenStudio::EnergyPlus::ForwardTranslator.new.translateModel(model)
        run_period = workspace.getObjectsByType('RunPeriod'.to_IddObjectType)[0]
      end
      assert_equal(year, run_period.getInt(run_period.iddObject.getFieldIndex('Begin Year').get).get)
      assert_equal(end_year, run_period.getInt(run_period.iddObject.getFieldIndex('End Year').get).get)
      assert_equal(weekday, run_period.getString(run_period.iddObject.getFieldIndex('Day of Week for Start Day').get).get)
    end
  end

  def test_apply_ground_temps_shallow
    model = OpenStudio::Model::Model.new
    hpxml = HPXML.new
    hpxml.buildings.add
    building = hpxml.buildings[0]
    [0.0, 10.0].each do |offset|
      monthly_celsius = Array.new(12) { |index| offset + index }
      monthly_fahrenheit = monthly_celsius.map { |temperature| temperature * 1.8 + 32.0 }
      weather = Struct.new(:data).new(Struct.new(:ShallowGroundMonthlyTemps).new(monthly_fahrenheit))

      Location.apply_ground_temps(model, weather, building)

      Date::MONTHNAMES[1..12].each_with_index do |month, index|
        assert_in_delta(monthly_celsius[index], model.getSiteGroundTemperatureShallow.public_send("#{month.downcase}SurfaceGroundTemperature"), 0.0001)
      end
      assert(model.getOptionalSiteGroundTemperatureDeep.empty?)
    end
  end

  def test_apply_ground_temps_deep
    model = OpenStudio::Model::Model.new
    hpxml = HPXML.new
    hpxml.buildings.add
    building = hpxml.buildings[0]
    building.heat_pumps.add(heat_pump_type: HPXML::HVACTypeHeatPumpGroundToAir)
    [10.0, 20.0].each do |temperature_celsius|
      data = Struct.new(:ShallowGroundMonthlyTemps, :DeepGroundAnnualTemp).new([50.0] * 12, temperature_celsius * 1.8 + 32.0)
      weather = Struct.new(:data).new(data)

      Location.apply_ground_temps(model, weather, building)

      Date::MONTHNAMES[1..12].each do |month|
        assert_in_delta(temperature_celsius, model.getSiteGroundTemperatureDeep.public_send("#{month.downcase}DeepGroundTemperature"), 0.0001)
      end
    end
  end

  def test_apply_year_requires_leap_weather
    header = HPXML.new.header
    header.sim_calendar_year = 2012
    weather = Struct.new(:header).new(Struct.new(:NumRecords).new(8760))
    error = assert_raises(RuntimeError) do
      Location.apply_year(OpenStudio::Model::Model.new, header, weather)
    end
    assert_includes(error.message, 'weather data has 8760 hours')
  end
end