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

  def test_always_off_discrete_schedule
    return unless Version::UseEPModel

    model = OpenStudio::Model::Model.new
    schedule = model.alwaysOffDiscreteSchedule
    assert_equal('Always Off Discrete', schedule.name.to_s)
    assert_equal(0.0, schedule.value)
    assert_equal('Discrete', schedule.scheduleTypeLimits.get.numericType.get)
    assert_equal(schedule.handle, model.alwaysOffDiscreteSchedule.handle)
    assert_equal(1, model.getScheduleConstants.count { |candidate| candidate.name.to_s == 'Always Off Discrete' })

    coil = OpenStudio::Model::CoilCoolingWater.new(model, schedule)
    assert_equal(schedule.handle, coil.availabilitySchedule.handle)
    other_model = OpenStudio::Model::Model.new
    refute_equal(schedule.handle, other_model.alwaysOffDiscreteSchedule.handle)

    schedule.setValue(1.0)
    assert_raises(RuntimeError) { model.alwaysOffDiscreteSchedule }
    schedule.setValue(0.0)
    schedule.resetScheduleTypeLimits
    assert_raises(RuntimeError) { model.alwaysOffDiscreteSchedule }
  end

  def test_microturbine_load_center_and_reporting
    return unless Version::UseEPModel

    model = OpenStudio::Model::Model.new
    generator = OpenStudio::Model::GeneratorMicroTurbine.new(model)
    generator.setReferenceElectricalPowerOutput(250.0)
    generator.additionalProperties.setFeature('ObjectType', Constants::ObjectTypeGenerator)
    power_curve = OpenStudio::Model::CurveBiquadratic.new(model)
    efficiency_curve = OpenStudio::Model::CurveCubic.new(model)
    generator.setElectricalPowerFunctionofTemperatureandElevationCurve(power_curve)
    generator.setElectricalEfficiencyFunctionofTemperatureCurve(efficiency_curve)
    generator.setElectricalEfficiencyFunctionofPartLoadRatioCurve(efficiency_curve)
    load_center = OpenStudio::Model::ElectricLoadCenterDistribution.new(model)
    assert(load_center.addGenerator(generator))

    assert_equal([generator.handle], model.getElectricLoadCenterDistributions.fetch(0).generators.map(&:handle))
    Outputs.create_custom_electricity_meters(model)
    workspace = OpenStudio::Workspace.new(model.toIdfFile)
    turbine = workspace.getObjectsByType('Generator:MicroTurbine'.to_IddObjectType).fetch(0)
    curve_fields = ['Electrical Power Function of Temperature and Elevation Curve Name',
                    'Electrical Efficiency Function of Temperature Curve Name',
                    'Electrical Efficiency Function of Part Load Ratio Curve Name']
    assert_equal([power_curve, efficiency_curve, efficiency_curve].map { |curve| curve.name.to_s },
                 curve_fields.map { |field| turbine.getString(turbine.iddObject.getFieldIndex(field).get).get })
    list = workspace.getObjectsByType('ElectricLoadCenter:Generators'.to_IddObjectType).fetch(0)
    assert_equal(250.0, list.getExtensibleGroup(0).getDouble(2).get)
    assert(workspace.getObjectsByType('Meter:CustomDecrement'.to_IddObjectType).any? do |meter|
      meter.extensibleGroups.any? { |group| group.getString(1).get == 'Generator Produced AC Electricity Energy' }
    end)
  end

  def test_pv_watts_load_center_and_reporting
    return unless Version::UseEPModel

    model = OpenStudio::Model::Model.new
    load_center = OpenStudio::Model::ElectricLoadCenterDistribution.new(model)
    inverter = OpenStudio::Model::ElectricLoadCenterInverterPVWatts.new(model)
    generator = OpenStudio::Model::GeneratorPVWatts.new(model, 5000.0)
    generator.additionalProperties.setFeature('ObjectType', Constants::ObjectTypePhotovoltaics)
    assert(load_center.setInverter(inverter))
    assert(load_center.addGenerator(generator))

    Outputs.create_custom_electricity_meters(model)
    workspace = OpenStudio::Workspace.new(model.toIdfFile)
    distribution = workspace.getObjectsByType('ElectricLoadCenter:Distribution'.to_IddObjectType).fetch(0)
    assert_equal('DirectCurrentWithInverter', distribution.getString(distribution.iddObject.getFieldIndex('Electrical Buss Type').get).get)
    assert_equal('Baseload', distribution.getString(distribution.iddObject.getFieldIndex('Generator Operation Scheme Type').get).get)
    assert_equal(inverter.name.to_s, distribution.getTarget(distribution.iddObject.getFieldIndex('Inverter Name').get).get.name.to_s)

    list = distribution.getTarget(distribution.iddObject.getFieldIndex('Generator List Name').get).get
    entry = list.getExtensibleGroup(0).to_WorkspaceExtensibleGroup.get
    assert_equal(generator.name.to_s, entry.getTarget(0).get.name.to_s)
    assert_equal('Generator:PVWatts', entry.getString(1).get)
    assert_equal(5000.0, entry.getDouble(2).get)
    assert_equal(5000.0, entry.getTarget(0).get.getDouble(generator.iddObject.getFieldIndex('DC System Capacity').get).get)

    meter = workspace.getObjectsByType('Meter:Custom'.to_IddObjectType).find { |object| object.name.to_s == 'Electricity:PV' }
    refute_nil(meter)
    assert_equal([[generator.name.to_s.upcase, 'Generator Produced DC Electricity Energy'],
                  [inverter.name.to_s.upcase, 'Inverter Conversion Loss Decrement Energy']],
                 meter.extensibleGroups.map { |group| [group.getString(0).get, group.getString(1).get] })
  end

  def test_electrical_storage_load_center_export
    return unless Version::UseEPModel

    model = OpenStudio::Model::Model.new
    load_center = OpenStudio::Model::ElectricLoadCenterDistribution.new(model)
    load_center.setElectricalBussType('AlternatingCurrentWithStorage')
    storage = OpenStudio::Model::ElectricLoadCenterStorageLiIonNMCBattery.new(model, 100, 2, 100.0, 1.0)
    assert(load_center.setElectricalStorage(storage))
    assert_equal(storage.handle, load_center.electricalStorage.get.handle)

    workspace = OpenStudio::Workspace.new(model.toIdfFile)
    distribution = workspace.getObjectsByType('ElectricLoadCenter:Distribution'.to_IddObjectType).fetch(0)
    target = distribution.getTarget(distribution.iddObject.getFieldIndex('Electrical Storage Object Name').get).get
    assert_equal('ElectricLoadCenter:Storage:LiIonNMCBattery', target.iddObject.name.to_s)
    assert_equal(storage.name.to_s, target.name.to_s)
  end

  def test_water_use_connection_equipment_and_schedules
    return unless Version::UseEPModel

    model = OpenStudio::Model::Model.new
    connection = OpenStudio::Model::WaterUseConnections.new(model)
    fixture_flow = Model.add_schedule_constant(model, name: 'Fixture Flow Fraction', value: 0.5)
    washer_flow = Model.add_schedule_constant(model, name: 'Washer Flow Fraction', value: 0.25)
    target_temp = Model.add_schedule_constant(model, name: 'Fixture Target Temperature', value: 40.0)

    fixture = Model.add_water_use_equipment(model, name: 'Fixture', end_use: nil, peak_flow_rate: 1.0e-6,
                                           flow_rate_schedule: fixture_flow, water_use_connections: connection, target_temperature_schedule: target_temp)
    washer = Model.add_water_use_equipment(model, name: 'Washer', end_use: nil, peak_flow_rate: 2.0e-6,
                                          flow_rate_schedule: washer_flow, water_use_connections: connection, target_temperature_schedule: nil)

    equipment = connection.waterUseEquipment
    assert_equal([fixture.handle, washer.handle], equipment.map(&:handle))
    assert_equal(fixture_flow.handle, equipment[0].flowRateFractionSchedule.get.handle)
    assert_equal(washer_flow.handle, equipment[1].flowRateFractionSchedule.get.handle)
    assert_equal(target_temp.handle, equipment[0].waterUseEquipmentDefinition.targetTemperatureSchedule.get.handle)
    refute(equipment[1].waterUseEquipmentDefinition.targetTemperatureSchedule.is_initialized)
  end

  def test_fan_speed_count_and_export
    return unless Version::UseEPModel

    model = OpenStudio::Model::Model.new
    fan = OpenStudio::Model::FanSystemModel.new(model)
    assert_equal(1, fan.numberofSpeeds)
    assert(fan.addSpeed(0.75, 0.5))
    assert_equal(1, fan.numberofSpeeds)
    assert(fan.addSpeed(1.0, 1.0))
    assert_equal(2, fan.numberofSpeeds)

    workspace = OpenStudio::Workspace.new(model.toIdfFile)
    exported_fan = workspace.getObjectsByType('Fan:SystemModel'.to_IddObjectType).fetch(0)
    assert_equal(2, exported_fan.getInt(exported_fan.iddObject.getFieldIndex('Number of Speeds').get).get)
    assert_equal([0.75, 1.0], exported_fan.extensibleGroups.map { |group| group.getDouble(0).get })
  end

  def test_zone_hvac_four_pipe_fan_coil_constructor
    return unless Version::UseEPModel

    model = OpenStudio::Model::Model.new
    schedule = model.alwaysOnDiscreteSchedule
    fan = OpenStudio::Model::FanConstantVolume.new(model, schedule)
    cooling_coil = OpenStudio::Model::CoilCoolingWater.new(model, schedule)
    heating_coil = OpenStudio::Model::CoilHeatingWater.new(model)

    fan_coil = OpenStudio::Model::ZoneHVACFourPipeFanCoil.new(model, schedule, fan, cooling_coil, heating_coil)

    assert_equal(schedule.handle, fan_coil.availabilitySchedule.handle)
    assert_equal(fan.handle, fan_coil.supplyAirFan.handle)
    assert_equal(cooling_coil.handle, fan_coil.coolingCoil.handle)
    assert_equal(heating_coil.handle, fan_coil.heatingCoil.handle)
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

  def test_wrapped_hpwh_plant_export
    return unless Version::UseEPModel

    model = OpenStudio::Model::Model.new
    plant_loop = OpenStudio::Model::PlantLoop.new(model)
    tank = OpenStudio::Model::WaterHeaterStratified.new(model)
    tank.heater1SetpointTemperatureSchedule.remove
    tank.heater2SetpointTemperatureSchedule.remove
    setpoint = Model.add_schedule_constant(model, name: 'HPWH Setpoint', value: 55.0)
    assert(tank.setHeater1SetpointTemperatureSchedule(setpoint))
    assert(tank.setHeater2SetpointTemperatureSchedule(setpoint))
    assert(plant_loop.addSupplyBranchForComponent(tank))
    coil = OpenStudio::Model::CoilWaterHeatingAirToWaterHeatPumpWrapped.new(model)
    fan = OpenStudio::Model::FanSystemModel.new(model)
    hpwh = OpenStudio::Model::WaterHeaterHeatPumpWrappedCondenser.new(model, coil, tank, fan, setpoint, model.alwaysOnDiscreteSchedule)

    workspace = OpenStudio::Workspace.new(model.toIdfFile)
    EPModelCompatibility.normalize_workspace(workspace, model)
    branch_group = workspace.getObjectsByType('Branch'.to_IddObjectType).flat_map(&:extensibleGroups).find do |group|
      group.getString(1).to_s == hpwh.name.to_s
    end
    refute_nil(branch_group)
    assert_equal('WaterHeater:HeatPump:WrappedCondenser', branch_group.getString(0).get)
    exported_hpwh = workspace.getObjectByTypeAndName('WaterHeater:HeatPump:WrappedCondenser'.to_IddObjectType, hpwh.name.to_s).get
    fields = ['Tank Name', 'DX Coil Name', 'Fan Name', 'Compressor Setpoint Temperature Schedule Name']
    assert_equal([tank, coil, fan, setpoint].map { |object| object.name.to_s },
                 fields.map { |field| exported_hpwh.getString(exported_hpwh.iddObject.getFieldIndex(field).get).get })
    equipment_groups = workspace.getObjectsByType('PlantEquipmentList'.to_IddObjectType).flat_map(&:extensibleGroups)
    assert_includes(equipment_groups.map { |group| [group.getString(0).to_s, group.getString(1).to_s] },
                    ['WaterHeater:HeatPump:WrappedCondenser', hpwh.name.to_s])
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