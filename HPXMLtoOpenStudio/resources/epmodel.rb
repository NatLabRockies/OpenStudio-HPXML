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
        field_index = @surface.iddObject.getFieldIndex('Space or SpaceList Name')
        if not field_index.is_initialized
          return false
        end

        return @surface.setPointer(field_index.get, space.handle)
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
  end

  unless OpenStudio::EPModel.const_defined?(:InternalMassDefinition, false)
    OpenStudio::EPModel.const_set(:InternalMassDefinition, EPModelCompatibility::InternalMassDefinition)
  end

  unless OpenStudio::EPModel.const_defined?(:InternalMass, false)
    OpenStudio::EPModel.const_set(:InternalMass, EPModelCompatibility::InternalMass)
  end

  unless OpenStudio::EPModel::Model.method_defined?(:getInternalMassDefinitions)
    OpenStudio::EPModel::Model.define_method(:getInternalMassDefinitions) do
      getInteriorPartitionSurfaces
    end
  end

  unless OpenStudio::EPModel::Model.method_defined?(:getShadingSurfaceGroups)
    OpenStudio::EPModel::Model.define_method(:getShadingSurfaceGroups) do
      getObjectsByType(OpenStudio::IddObjectType.new('OS_ShadingSurfaceGroup'))
    end
  end

  if not OpenStudio::EPModel::ModelObject.method_defined?(:additionalProperties)
    OpenStudio::EPModel::ModelObject.define_method(:additionalProperties) do
      EPModelCompatibility::AdditionalProperties.for_object(self)
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
end