# frozen_string_literal: true

require 'attr_memoized/version'
# This module, when included, decorates the receiver with several useful
# methods:
#
# * Both class and instance methods #mutex are added, that can be used
#   to guard any shared resources. Each class gets their own class attr_memoized_mutex.
#   and each instance gets it's own separate attr_memoized_mutex.
#
# * new class method #attr_memoized is added, the syntax is as follows:
#
#        attr_memoized :attribute_name, ..., -> { block returning a value }
#
# * the block in the definition above is called via #instance_exec on the
#   object (instance of a class) and therefore has access to all private
#   methods. If the value is a symbol, it is expected to be a method.
#
# * multiple attribute names are allowed in the #attr_memoized, but they
#   will all be assigned the result of the block (last argument) when called.
#   Therefore, typically you would use #attr_memoized with one attribute at
#   a time, unless you want to have several version of the same variable:
#
# @example
#
#  class RandomNumbers
#     include AttrMemoized
#
#     attr_memoized :random, -> { rand(10) },            writer: false
#     attr_memoized :seed,   -> { Time.now.to_i % 57 }
#
#     attr_memoized :number1, :number2, -> { self.class.incr! && rand(10) }
#
#     @calls = 0
#     class << self
#       attr_reader :calls
#       def incr!; @calls = 0 unless defined(@calls); @calls += 1 ; end
#     end
#   end
#
#   @rn = RandomNumbers.new
#
#   # first call executes the block, and caches it
#   @rn.number1                          # => 3
#   # and it's saved now, and the block is no longer called
#   @rn.number1                          # => 3
#   @rn.number2                          # => 9
#   @rn.number2                          # => 9
#   # only 2 times did we ever call incr! method
#   @rn.class.calls                      # => 2
#
#   # Now #seed is also lazy-loaded, and also cached
#   @rn.seed                             # => 34
#   # And, we can change it thread safely!
#   @rn.seed = 64; @rn.seed              # => 64
#
#   # Not so with :random, which was defined without the writer:
#   @rn.random                           # => 8
#   @rn.random = 34
#   # => NoMethodError: undefined method `random=' for #<RandomNumbers:0x007ffb28105178>
#
#
module AttrMemoized
  # We are being a bit paranoid here, so yes we are creating
  # a central lock used to initialize other class-specific attr_memoized_mutex.s.
  # This should only be a problem if you are constantly defining new
  # classes that include +AttrMemoized++
  LOCK = Mutex.new.freeze unless defined?(LOCK)
  #
  # The types of initializers we support.
  SUPPORTED_INIT_TYPES = [Proc, Method, Symbol].freeze

  class << self
    def included(base)
      base.class_eval do
        AttrMemoized::LOCK.synchronize do
          @attr_memoized_mutex ||= Mutex.new
        end

        # noinspection ALL
        class << self
          attr_reader :attr_memoized_mutex

          # A class method which, for each attribute in the list,
          # creates a thread-safe memoized reader and writer (unless writer: false)
          #
          # Memoized reader accepts <tt>reload: true</tt> as an optional argument,
          # which, if provided, forces reinitialization of the variable.
          #
          # @example:
          #
          #   class LazyConnection
          #     include AttrMemoized
          #     attr_memoized :database_connection, -> { ActiveRecord::Base.connection }
          #     attr_memoized :redis_pool, -> { ConnectionPool.new { Redis.new } }
          #   end
          #
          #   LazyConnection.new.database_connection
          #   #=> <ActiveRecord::Connection::PgSQL::Driver:0xff23234f....>
          #
          # @param [Symbol] name of the attribute
          # @param [Symbol] another name of the attribute, etc...
          # @param [Proc,Symbol,Method] callable — something to call for lazy initialization
          # @param [Hash] options — you can define arguments here to be passed to a method or proc
          def attr_memoized(*attributes, **opts)
            attributes = Array[*attributes]
            callable   = attributes.pop
            unless SUPPORTED_INIT_TYPES.include?(callable.class)
              raise ArgumentError, "Invalid argument #{callable} to attr_memoized. Expecting one of: #{SUPPORTED_INIT_TYPES.map(&:to_s)}"
            end

            writer = opts.delete(:writer)
            attributes.each do |attribute|
              __define_attribute_writer(attribute, **opts) unless writer == false
              __define_attribute_reader(attribute, callable, **opts)
            end
          end

          # Memoized Reader only
          def attr_memoized_reader(*attrs, **opts)
            attr_memoized(*attrs, writer: false, **opts)
          end

          private

          def __define_attribute_reader(attribute, callable, **opts)
            at_attribute = __at_var(attribute)
            define_method(attribute) do |*|
              __read_memoize(attribute, at_attribute, callable, **opts)
            end
          end

          def __define_attribute_writer(attribute, **_opts)
            at_attribute = __at_var(attribute)
            define_method("#{attribute}=".to_sym) do |value|
              with_lock { instance_variable_set(at_attribute, value) }
              value
            end
          end

          # Convert an attribute name into an @variable syntax
          def __at_var(attr)
            attr = attr.to_sym unless attr.is_a?(Symbol)
            @attr_cache ||= {}
            @attr_cache[attr] || (@attr_cache[attr] = "@#{attr}".to_sym)
          end
        end

        # instance method: uses the class +attr_memoized_mutex+ to create an instance
        # attr_memoized_mutex and then uses the instance attr_memoized_mutex to wrap instance's state
        # @return [Mutex] mutex
        def attr_memoized_mutex
          return @attr_memoized_mutex if @attr_memoized_mutex

          self.class.attr_memoized_mutex.synchronize {
            @attr_memoized_mutex ||= Mutex.new
          }
        end
      end
    end
  end

  # This method offers "thread-local locking": meaning that the synchronize
  # block is never called twice from the same thread, thus avoiding deadlocks.
  #
  # @param [Proc] block block to wrap in a synchronize unless we are already under one
  def with_lock(&block)
    if __locked?
      block.call
    else
      __with_thread_local_lock { attr_memoized_mutex.synchronize(&block) }
    end
  end

  private

  # This private method is executed in order to initialize a memoized
  # attribute.
  #
  # @param [Symbol] attribute - name of the attribute
  # @param [Symbol] at_attribute - symbol representing attribute instance variable
  # @param [Proc, Method, Symbol] callable - what to call to get the uncached value
  # @param [Hash] opts - additional options
  # @option opts [Boolean] :reload - forces re-initialization of the memoized attribute
  def __read_memoize(attribute, at_attribute, callable, **opts)
    var = instance_variable_get(at_attribute)
    return var if var && !__reload?(opts)

    with_lock { __assign_value(attribute, at_attribute, callable, **opts) }
    instance_variable_get(at_attribute)
  end

  # This private method resolves the initializer argument and returns it's result.
  def __assign_value(attribute, at_attribute, callable, **opts)
    # reload the value of +var+ because we are now inside a synchronize block
    var = instance_variable_get(at_attribute)
    return var if var && !__reload?(opts)

    # now call whatever `was defined on +attr_memoized+ to get the actual value
    case callable
    when Symbol
      send(callable, **opts)
    when Method
      callable.call(**opts)
    when Proc
      instance_exec(&callable)
    else
      raise ArgumentError, "expected one of #{AttrMemoized::SUPPORTED_INIT_TYPES.map(&:to_s).join(', ')} for attribute #{attribute}, got #{callable.class}"
    end.tap do |result|
      instance_variable_set(at_attribute, result)
    end
  end

  # Returns +true+ if +opts+ contains reload: +true+
  def __reload?(opts)
    opts.delete(:reload)
  end

  # just a key into Thread.local
  def __object_lock_key
    @key ||= "this.#{object_id}".to_sym
  end

  def __locked?
    Thread.current[__object_lock_key]
  end

  def __with_thread_local_lock
    raise ArgumentError, 'Already locked!' if __locked?

    Thread.current[__object_lock_key] = true
    yield if block_given?
    Thread.current[__object_lock_key] = nil
  end
end
