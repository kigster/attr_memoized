require 'attr_memoized/version'

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
# Example
# =======
#
#      class RandomNumbers
#         include AttrMemoized
#
#         attr_memoized :random, -> { rand(10) },            writer: false
#         attr_memoized :seed,   -> { Time.now.to_i % 57 }
#
#         attr_memoized :number1, :number2, -> { self.class.incr! && rand(10) }
#
#         @calls = 0
#         class << self
#           attr_reader :calls
#           def incr!; @calls = 0 unless defined(@calls); @calls += 1 ; end
#         end
#       end
#
#       @rn = RandomNumbers.new
#
#       # first call executes the block, and caches it
#       @rn.number1                          # => 3
#       # and it's saved now, and the block is no longer called
#       @rn.number1                          # => 3
#       @rn.number2                          # => 9
#       @rn.number2                          # => 9
#       # only 2 times did we ever call incr! method
#       @rn.class.calls                      # => 2
#
#       # Now #seed is also lazy-loaded, and also cached
#       @rn.seed                             # => 34
#       # And, we can change it thread safely!
#       @rn.seed = 64; @rn.seed              # => 64
#
#       # Not so with :random, which was defined without the writer:
#       @rn.random                           # => 8
#       @rn.random = 34
#       # => NoMethodError: undefined method `random=' for #<RandomNumbers:0x007ffb28105178>
#
#
module AttrMemoized

  # We are being a bit paranoid here, so yes we are creating
  # a central lock used to initialize other class-specific mutexes.
  # This should only be a problem if you are constantly defining new
  # classes that include +AttrMemoized++
  LOCK = Mutex.new.freeze unless defined?(LOCK)

  class << self
    # that's obviously a joke. The name, I mean. Duh.
    attr_accessor :gil

    def included(base)
      base.class_eval do
        AttrMemoized::LOCK.synchronize do
          @mutex ||= Mutex.new
        end

        class << self
          attr_reader :mutex
          #
          # Class level method that for each attribute in the list
          # creates thread-safe memoized accessor, that expects only
          # options has as argument (refresh: true | false), but provides
          # a block for initially setting the value
          #
          def attr_memoized(*attributes, **opts)
            attributes    = Array[*attributes]
            block_or_proc = attributes.pop if [Proc, Method, Symbol].include?(attributes.last.class)
            attributes.each do |attribute|
              define_attribute_writer(attribute) unless opts && opts.has_key?(:writer) && opts[:writer].eql?(false)
              define_attribute_reader(attribute, block_or_proc)
            end
          end

          def define_attribute_reader(attribute, block_or_proc)
            at_attribute = at(attribute)
            define_method(attribute) do |**opts|
              thread_safe_memoize(attribute, at_attribute, block_or_proc, **opts)
            end
          end

          def define_attribute_writer(attribute)
            at_attribute = at(attribute)
            define_method("#{attribute}=".to_sym) do |value|
              mutex.synchronize do
                self.instance_variable_set(at_attribute, value)
              end
            end
          end

          private

          # Convert an attribute name into an @variable syntax
          def at(attr)
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
          self.class.mutex.synchronize {
            @mutex ||= Mutex.new
          }
        end
      end
    end
  end

  #
  # @param [Symbol] attribute —  name of the attribute
  # @param [Symbol] @attribute —  symbol representing instance variable
  # @param [Proc | Method | Symbol] —  what to call to get the uncached value
  # @param [Hash] opts  —  if true, forces refetching of the value by calling
  #                        the block given.
  def thread_safe_memoize(attribute, at_attribute, block_or_proc, **opts)
    refresh = (opts && opts.has_key?(:refresh)) ? opts[:refresh] : nil

    # quickly return if we already have the value, and refresh was not
    # set to true
    var = self.instance_variable_get(at_attribute)
    return var if refresh.nil? && var

    # this is the part that can get gobbled up if multiple threads are
    # calling it, so wrap it in mutex.
    self.mutex.synchronize do
      # do second check, in case this was defined during a race condition
      var = self.instance_variable_get(at_attribute)
      return var if (var && !refresh)

      result = case block_or_proc
                 when Symbol
                   self.send(block_or_proc)
                 when Method
                   method.call
                 when Proc
                   instance_exec(&block_or_proc)
                 else
                   raise ArgumentError, "expecting either a method name, method, or a block for attribute #{attribute}, block_or_method type #{block_or_proc.class}"
               end

      result.tap do |v|
        self.instance_variable_set(at_attribute, v)
      end
    end
  end
end
