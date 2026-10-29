require_relative '../resources/minitest_helper'
require 'openstudio'
require_relative '../measure.rb'

class HPXMLtoOpenStudioEPModelTest < Minitest::Test
  def test_model_namespace
    if Version::UseEPModel
      assert_same(OpenStudio::EPModel, OpenStudio::Model)
      assert_same(OpenStudio::EPModel::Model, OpenStudio::Model::Model)
    else
      assert_equal('OpenStudio::Model', OpenStudio::Model.name)
    end
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