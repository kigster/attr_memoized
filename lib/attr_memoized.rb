# frozen_string_literal: true

require 'attr_memoized/version'
require 'thread'

# This module, when included, decorates the receiver with several useful
# methods:
#
# * Both class and instance methods #mutex are added, that can be used
#   to guard any shared resources. Each class gets their own class mutex,
#   and each instance gets it's own separate mutex.
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
  # a central lock used to initialize other class-specific mutexes.
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
          def attr_memoized(*attributes, **opts)
            attributes    = Array[*attributes]
            block_or_proc = attributes.pop if SUPPORTED_INIT_TYPES.include?(attributes.last.class)
            attributes.each do |attribute|
              __define_attribute_writer(attribute) unless opts && opts.has_key?(:writer) && opts[:writer].eql?(false)
              __define_attribute_reader(attribute, block_or_proc)
            end
          end

          private

          def __define_attribute_reader(attribute, block_or_proc)
            at_attribute = __at_var(attribute)
            define_method(attribute) do |**opts|
              __read_memoize(attribute, at_attribute, block_or_proc, **opts)
            end
          end

          def __define_attribute_writer(attribute)
            at_attribute = __at_var(attribute)
            define_method("#{attribute}=".to_sym) do |value|
              with_lock { self.instance_variable_set(at_attribute, value) }
              value
            end
          end

          # Convert an attribute name into an @variable syntax
          def __at_var(attr)
            attr        = attr.to_sym unless attr.is_a?(Symbol)
            @attr_cache ||= {}
            @attr_cache[attr] || (@attr_cache[attr] = "@#{attr}".to_sym)
          end
        end

        # instance method: uses the class mutex to create an instance
        # mutex, and then uses the instance mutex to wrap instance's
        # state
        def mutex
          return @mutex if @mutex
          self.class.attr_memoized_mutex.synchronize {
            @mutex ||= Mutex.new
          }
        end
      end
    end
  end

  # This public method is offered in place of a local +mutex+'s
  # synchronize method to guard state changes to the object using
  # object's mutex and a thread-local flag. The flag prevents
  # duplicate synchronize within the same thread on the same +mutex+.
  #
  # @param [Proc] block block to wrap in a synchronize unless we are already under one
  def with_lock(&block)
    if __locked?
      block.call
    else
      __with_thread_local_lock { mutex.synchronize(&block) }
    end
  end

  private

  # This private method is executed in order to initialize a memoized
  # attribute.
  #
  # @param [Symbol] attribute - name of the attribute
  # @param [Symbol] at_attribute - symbol representing attribute instance variable
  # @param [Proc, Method, Symbol] block_or_proc - what to call to get the uncached value
  # @param [Hash] opts - additional options
  # @option opts [Boolean] :reload - forces re-initialization of the memoized attribute
  def __read_memoize(attribute, at_attribute, block_or_proc, **opts)
    var = self.instance_variable_get(at_attribute)
    return var if var && !__reload?(opts)
    with_lock { __assign_value(attribute, at_attribute, block_or_proc, **opts) }
    self.instance_variable_get(at_attribute)
  end

  # This private method resolves the initializer argument and returns it's result.
  def __assign_value(attribute, at_attribute, block_or_proc, **opts)
    # reload the value of +var+ because we are now inside a synchronize block
    var = self.instance_variable_get(at_attribute)
    return var if (var && !__reload?(opts))

    # now call whatever `was defined on +attr_memoized+ to get the actual value
    case block_or_proc
    when Symbol
      send(block_or_proc)
    when Method
      block_or_proc.call
    when Proc
      instance_exec(&block_or_proc)
    else
      raise ArgumentError, "expected one of #{AttrMemoized::SUPPORTED_INIT_TYPES.map(&:to_s).join(', ')} for attribute #{attribute}, got #{block_or_proc.class}"
    end.tap do |result|
      self.instance_variable_set(at_attribute, result)
    end
  end

  # Returns +true+ if +opts+ contains reload: +true+
  def __reload?(opts)
    (opts && opts.has_key?(:reload)) ? opts[:reload] : nil
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
