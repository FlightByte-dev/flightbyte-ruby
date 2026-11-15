# frozen_string_literal: true

module FlightByte
  # A read-only view of a JSON object the API sent.
  #
  # Fields read as methods with snake_case names (`flight.departure.delay_minutes`),
  # or with `[]` and the API's own camelCase key (`flight["departure"]["delayMinutes"]`).
  # {#to_h} returns the JSON exactly as it was received.
  #
  # Each response has its own subclass, such as {FlightSnapshot} or
  # {Subscription}, that declares the fields this version knows. A known field
  # the API left out reads as `nil`, so a delay of `0` and no delay reading stay
  # apart. A field the API added after this release still reads as a method
  # and with `[]`; a name that is neither raises `NoMethodError`, so a typo does
  # not pass for a missing value.
  #
  # Objects are frozen and safe to share between threads. Timestamps stay ISO
  # 8601 strings and enums stay strings, exactly as the API sent them.
  class Object
    @fields = {}.freeze

    class << self
      # The fields this class declares: the API's key to the type its value is
      # wrapped in (`nil` for a plain JSON value).
      #
      # @return [Hash{String => Object}]
      attr_reader :fields

      # The snake_case method name for an API key: `delayMinutes` reads as
      # `delay_minutes`.
      #
      # @param key [String]
      # @return [String]
      def method_name(key)
        key.to_s
           .gsub(/([A-Z\d]+)([A-Z][a-z])/, '\1_\2')
           .gsub(/([a-z\d])([A-Z])/, '\1_\2')
           .tr("-", "_")
           .downcase
      end

      # @api private
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@fields, fields)
      end

      # @api private
      # Wraps already frozen JSON without copying it again.
      def build(frozen)
        allocate.tap { |object| object.send(:setup, frozen) }
      end

      # @api private
      # Wraps a decoded response body, which must be a JSON object.
      def from_response(data)
        unless data.is_a?(Hash)
          raise Error, "flightbyte: expected a JSON object from the API for #{name}, got #{data.inspect[0, 100]}"
        end

        build(deep_freeze_copy(data))
      end

      # @api private
      # Wraps the `data` list of a decoded `{ count, data }` response.
      def list_from_response(data)
        list = data.is_a?(Hash) ? data["data"] : nil
        unless list.is_a?(Array)
          raise Error, "flightbyte: expected a JSON object with a data list from the API for #{name}"
        end

        list.map { |item| from_response(item) }.freeze
      end

      private

      # Declares a field: a reader named after `key` in snake_case, and with
      # `predicate: true` a `?` reader that is true only when the API sent `true`.
      #
      # `type` is a subclass to wrap an object in, `[Subclass]` for a list of
      # them, or `:map` for a map of your own strings such as `metadata`, which
      # reads as a frozen `Hash`.
      def field(key, type = nil, predicate: false)
        @fields = fields.merge(key => type).freeze
        name = Object.method_name(key)
        define_method(name) { @values[key] }
        define_method("#{name}?") { @values[key] == true } if predicate
        name.to_sym
      end
    end

    # Wraps `data`, a Hash shaped like the API's JSON. Keys may be strings or
    # symbols; the data is copied, so changing `data` later changes nothing here.
    #
    # @param data [Hash]
    def initialize(data = {})
      raise TypeError, "flightbyte: #{self.class} needs a Hash, got #{data.class}." unless data.is_a?(Hash)

      setup(Object.deep_freeze_copy(data))
    end

    # The value under the API's own key, wrapped as the method would return it.
    #
    # @param key [String, Symbol] the camelCase key, for example `"delayMinutes"`
    # @return [Object, nil]
    def [](key)
      @values[key.to_s]
    end

    # Reads a nested value, as `Hash#dig` does: `flight.dig("departure", "gate")`.
    #
    # @return [Object, nil]
    def dig(key, *rest)
      value = self[key]
      return value if rest.empty? || value.nil?

      value.dig(*rest)
    end

    # Whether the API sent `key`, even as `null`.
    #
    # @param key [String, Symbol]
    def key?(key)
      @raw.key?(key.to_s)
    end

    # The keys the API sent, in its order.
    #
    # @return [Array<String>]
    def keys
      @raw.keys
    end

    # The JSON exactly as the API sent it, with string keys. A fresh copy each
    # time, so changing it changes nothing here.
    #
    # @return [Hash{String => Object}]
    def to_h
      Object.deep_copy(@raw)
    end

    # The JSON as received; used by Rails' `render json:`.
    #
    # @return [Hash{String => Object}]
    def as_json(*)
      to_h
    end

    # The JSON as received, serialized.
    #
    # @return [String]
    def to_json(*args)
      to_h.to_json(*args)
    end

    # Pattern matching with snake_case keys:
    #
    #   case flight
    #   in { status: { phase: "landed" | "arrived" }, arrival: { gate: String => gate } }
    #     puts "Landed at gate #{gate}"
    #   end
    #
    # @return [Hash{Symbol => Object}]
    def deconstruct_keys(keys)
      names = self.class.fields.keys.to_h { |key| [Object.method_name(key).to_sym, key] }.merge(@extra)
      names = names.slice(*keys) if keys
      names.transform_values { |key| @values[key] }
    end

    # Equal when the class and the JSON are the same.
    def ==(other)
      other.instance_of?(self.class) && other.raw == @raw
    end
    alias eql? ==

    # @return [Integer]
    def hash
      [self.class, @raw].hash
    end

    # Shows the JSON, with any signing secret masked so it stays out of logs.
    #
    # @return [String]
    def inspect
      "#<#{self.class.name} #{Object.mask_secrets(@raw).inspect}>"
    end
    alias to_s inspect

    # @api private
    def pretty_print(printer)
      printer.text(inspect)
    end

    # @api private
    def respond_to_missing?(name, include_private = false)
      @extra.key?(name) || super
    end

    # @api private
    def method_missing(name, *args, &block)
      key = @extra[name]
      return super if key.nil? || !args.empty? || block

      @values[key]
    end

    protected

    # @api private
    attr_reader :raw

    private

    def setup(frozen)
      fields = self.class.fields
      @raw = frozen
      @values = {}
      @extra = {}
      frozen.each do |key, value|
        @extra[Object.method_name(key).to_sym] = key unless fields.key?(key)
        @values[key] = Object.wrap(value, fields[key])
      end
      @values.freeze
      @extra.freeze
      freeze
    end

    class << self
      # @api private
      def wrap(value, type)
        case value
        when Hash
          return value if type == :map

          (type.is_a?(Class) && type <= Object ? type : Object).build(value)
        when Array
          element = type.is_a?(Array) ? type.first : nil
          value.map { |item| wrap(item, element) }.freeze
        else
          value
        end
      end

      # @api private
      def deep_freeze_copy(value)
        case value
        when Hash then value.to_h { |key, item| [key.to_s.dup.freeze, deep_freeze_copy(item)] }.freeze
        when Array then value.map { |item| deep_freeze_copy(item) }.freeze
        when String then value.frozen? ? value : value.dup.freeze
        when Object then deep_freeze_copy(value.to_h)
        else value
        end
      end

      # @api private
      def deep_copy(value)
        case value
        when Hash then value.to_h { |key, item| [key, deep_copy(item)] }
        when Array then value.map { |item| deep_copy(item) }
        when String then value.dup
        else value
        end
      end

      # @api private
      def mask_secrets(value)
        case value
        when Hash
          value.to_h do |key, item|
            [key, key == "secret" && item.is_a?(String) ? FlightByte.mask_secret(item) : mask_secrets(item)]
          end
        when Array then value.map { |item| mask_secrets(item) }
        else value
        end
      end
    end
  end
end
