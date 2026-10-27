# frozen_string_literal: true

require_relative "../base/text"
require_relative "../json/num"
require_relative "../json/writer"

module Callmend
  module Schema
    module Validator
      module_function

      TYPE_NAMES = %w[null boolean integer number string array object].freeze

      def problems(schema, value, path = "$")
        return [] unless schema.is_a?(Hash)

        issues = []
        type_names = valid_type_names(schema["type"])
        if type_names&.none? { |type_name| type_matches?(type_name, value) }
          return [[path, "expected #{type_names.join(" or ")}, got #{kind_of(value)}"]]
        end

        if schema["enum"].is_a?(Array) && schema["enum"].none? { |candidate| json_equal?(candidate, value) }
          issues << [path, "value is not one of #{Json::Writer.dump(schema["enum"])}"]
        end

        if schema.key?("const") && !json_equal?(schema["const"], value)
          issues << [path, "value is not #{Json::Writer.dump(schema["const"])}"]
        end

        case value
        when String
          validate_string(schema, value, path, issues)
        when Json::Num
          validate_number(schema, value, path, issues)
        when Hash
          validate_object(schema, value, path, issues)
        when Array
          validate_array(schema, value, path, issues)
        end

        issues
      end

      def kind_of(value)
        case value
        when NilClass then "null"
        when TrueClass, FalseClass then "boolean"
        when String then "string"
        when Json::Num then value.integer_text? ? "integer" : "number"
        when Array then "array"
        when Hash then "object"
        else "unknown"
        end
      end

      def valid_type_names(type)
        names = type.is_a?(Array) ? type : [type]
        return unless !names.empty? && names.all? { |name| name.is_a?(String) && TYPE_NAMES.include?(name) }

        names
      end
      private_class_method :valid_type_names

      def type_matches?(type_name, value)
        case type_name
        when "null" then value.nil?
        when "boolean" then value.equal?(true) || value.equal?(false)
        when "integer" then value.is_a?(Json::Num) && value.whole?
        when "number" then value.is_a?(Json::Num)
        when "string" then value.is_a?(String)
        when "array" then value.is_a?(Array)
        when "object" then value.is_a?(Hash)
        end
      end
      private_class_method :type_matches?

      def validate_string(schema, value, path, issues)
        minimum = valid_limit(schema["minLength"])
        maximum = valid_limit(schema["maxLength"])
        length = value.length

        issues << [path, "string is shorter than #{Text.plural(minimum, "character")}"] if minimum && length < minimum
        return unless maximum && length > maximum

        issues << [path, "string is longer than #{Text.plural(maximum, "character")}"]
      end
      private_class_method :validate_string

      def validate_number(schema, value, path, issues)
        minimum = schema["minimum"]
        if numeric_bound?(minimum) && value.to_r < minimum.to_r
          issues << [path, "number is below the minimum #{minimum.text}"]
        end

        maximum = schema["maximum"]
        return unless numeric_bound?(maximum) && value.to_r > maximum.to_r

        issues << [path, "number is above the maximum #{maximum.text}"]
      end
      private_class_method :validate_number

      def validate_object(schema, value, path, issues)
        required = schema["required"]
        if required.is_a?(Array) && required.all?(String)
          required.each do |name|
            issues << [path, "missing required property #{Json::Writer.quote(name)}"] unless value.key?(name)
          end
        end

        properties = schema["properties"]
        property_schemas = properties.is_a?(Hash) ? properties : {}
        property_schemas.each do |name, child_schema|
          next unless value.key?(name)

          issues.concat(problems(child_schema, value[name], property_path(path, name)))
        end

        return unless schema["additionalProperties"].equal?(false)

        value.each_key do |name|
          next if property_schemas.key?(name)

          issues << [path, "unexpected property #{Json::Writer.quote(name)}"]
        end
      end
      private_class_method :validate_object

      def validate_array(schema, value, path, issues)
        minimum = valid_limit(schema["minItems"])
        maximum = valid_limit(schema["maxItems"])

        issues << [path, "array has fewer than #{Text.plural(minimum, "item")}"] if minimum && value.length < minimum
        issues << [path, "array has more than #{Text.plural(maximum, "item")}"] if maximum && value.length > maximum

        item_schema = schema["items"]
        return unless item_schema.is_a?(Hash)

        value.each_with_index do |item, index|
          issues.concat(problems(item_schema, item, "#{path}[#{index}]"))
        end
      end
      private_class_method :validate_array

      def valid_limit(value)
        return unless value.is_a?(Json::Num) && value.integer_text?

        limit = Integer(value.text, 10)
        limit if limit >= 0
      end
      private_class_method :valid_limit

      def numeric_bound?(value)
        return false unless value.is_a?(Json::Num)

        value.to_r
        true
      rescue ArgumentError
        false
      end
      private_class_method :numeric_bound?

      def json_equal?(left, right)
        return right.is_a?(Json::Num) && left.to_r == right.to_r if left.is_a?(Json::Num)
        return false if right.is_a?(Json::Num)
        return false unless left.instance_of?(right.class)

        case left
        when NilClass, TrueClass, FalseClass, String
          left == right
        when Array
          left.length == right.length && left.zip(right).all? do |left_item, right_item|
            json_equal?(left_item, right_item)
          end
        when Hash
          left.length == right.length &&
            left.all? { |key, left_value| right.key?(key) && json_equal?(left_value, right[key]) }
        else
          false
        end
      end
      private_class_method :json_equal?

      def property_path(path, name)
        if name.is_a?(String) && /\A[A-Za-z_][A-Za-z0-9_]*\z/.match?(name)
          "#{path}.#{name}"
        else
          "#{path}[#{Json::Writer.quote(name)}]"
        end
      end
      private_class_method :property_path
    end
  end
end
