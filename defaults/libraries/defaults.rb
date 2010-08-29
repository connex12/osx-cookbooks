require 'chef/resource'

class Chef::Resource::Defaults < Chef::Resource
  def initialize(domain, key, run_context = nil)
    super("#{domain} #{key}", run_context)

    @domain = domain
    @key = key
    @type = nil
    @value = nil

    @resource_name = :defaults
    @action = "run"
    @allowed_actions.push(:run)
  end

  def domain(arg = nil)
    set_or_return(:domain, arg, :kind_of => [String])
  end

  def key(arg = nil)
    set_or_return(:key, arg, :kind_of => [String])
  end

  def type(arg = nil)
    set_or_return(:type, arg, :kind_of => [String])
  end

  def value(arg = nil)
    set_or_return(:value, arg, {})
  end
end


require 'chef/provider'

class Chef::Provider::Defaults < Chef::Provider
  def self.decoders
    @decoders ||= {}
  end

  def self.encoders
    @encoders ||= {}
  end

  def self.decoder(type, &block)
    decoders[type.to_s] = block
  end

  def self.encoder(type, &block)
    encoders[type.to_s] = block
  end


  decoder :boolean do |value|
    case value
    when '1', 'YES'
      true
    when '0', 'NO'
      false
    else
      nil
    end
  end

  encoder :boolean do |obj|
    case obj
    when TrueClass
      'YES'
    when FalseClass, NilClass
      'NO'
    else
      nil
    end
  end

  decoder :string do |value|
    value
  end

  encoder :string do |obj|
    if obj.respond_to?(:to_str)
      obj
    else
      nil
    end
  end


  include Chef::Mixin::Command

  def load_current_resource
    domain = new_resource.domain
    key    = new_resource.key

    @current_resource = Chef::Resource::Defaults.new(domain, key)

    status, stdout, stderr = output_of_command("defaults read-type #{domain} #{key}", {})
    if status == 0 && stdout =~ /Type is (\w+)/
      @current_resource.type($1)
    end

    if @new_resource.type.nil?
      @new_resource.type(@current_resource.type)
    end

    status, stdout, stderr = output_of_command("defaults read #{domain} #{key}", {})
    if status == 0
      value = decode(@current_resource.type, stdout)
      @current_resource.value(value)
    end

    @current_resource
  end

  def action_run
    if @current_resource.type == @new_resource.type &&
        @current_resource.value == @new_resource.value
      Chef::Log.debug "Skipping #{@new_resource} since the value is already set"
    else
      if @new_resource.type.nil?
        @new_resource.type(guess_type(@new_resource.value))
      end

      domain = @new_resource.domain
      key    = @new_resource.key
      type   = @new_resource.type
      value  = encode(type, @new_resource.value)

      command = "defaults write #{domain} #{key} -#{type} #{value.inspect}"

      if run_command(:command => command, :command_string => @new_resource.to_s)
        @new_resource.updated = true
        Chef::Log.info("Ran #{@new_resource} successfully")
      end
    end
  end

  private
    def decode(type, value)
      self.class.decoders[type].call(value)
    end

    def encode(type, obj)
      self.class.encoders[type].call(obj)
    end

    def guess_type(obj)
      Chef::Log.debug "Guessing defaults type for #{obj.inspect}"
      self.class.encoders.each do |type, encoder|
        if obj = encoder.call(obj)
          return type
        end
      end
      nil
    end
end