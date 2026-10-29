require_relative '../resources/minitest_helper'
require 'openstudio'
require_relative '../measure.rb'

class HPXMLtoOpenStudioEPModelTest < Minitest::Test
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