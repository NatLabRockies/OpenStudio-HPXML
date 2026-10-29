require 'date'
require_relative 'version'

if Version::UseEPModel
  OpenStudio.send(:remove_const, :Model)
  OpenStudio.const_set(:Model, OpenStudio::EPModel)

  module EPModelCompatibility
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
  end

  if not OpenStudio::EPModel::ModelObject.method_defined?(:additionalProperties)
    OpenStudio::EPModel::ModelObject.define_method(:additionalProperties) do
      EPModelCompatibility::AdditionalProperties.for_object(self)
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
end