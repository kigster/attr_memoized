require 'attr_memoized/version'

# This module, when included, decorates the receiver with several useful
# methods:
#
#   1. Both class and instance methods #mutex are added, that can be used
#      to guard any shared resources. Each class gets their own class mutex,
#      and each instance gets it's own separate mutex.
#
#   2. new class method #attr_memoized is added, the syntax is as follows:
#
#          attr_memoized :attribute_name, ..., -> { block returning a value }
#a
#   3. the block in the definition above is called via #instance_exec on the
#      object (instance of a class) and therefore has access to all private
#      methods. If the value is a symbol, it is expected to be a method.
#
#   4. multiple attribute names are allowed in the #attr_memoized, but they
#      will all be assigned the result of the block (last argument) when called.
#      Therefore, typically you would use #attr_memoized with one attribute at
#      a time, unless you want to have several version of the same variable:
#
# Example
# =======
#
#          class RandomNumbers
#            include AttrMemoized
#            @calls = 0
#            class << self
#              attr_reader :calls
#              def called; @calls += 1; end
#            end
#
#            attr_memoized :number1, :number2, -> { self.class.called; rand(10) }
#          end
#
#          @rn = RandomNumbers.new
#
#          @rn.instance_variable_get(:@number1) # => nil
#          @rn.number1                          # => 3
#          # and it's saved now:
#          @rn.number1                          # => 3
#
#          @rn.instance_variable_get(:@number2) # => nil
#          @rn.number2                          # => 7
#          # and it's saved now:
#          @rn.number2                          # => 7
#
#          @rn.class.calls                      # => 2
#
module AttrMemoized
  class << self
    def included(base)
      base.class_eval do
        @mutex = Mutex.new
        class << self
          attr_reader :mutex
          # Class level method that for each attribute in the list
          # creates thread-safe memoized accessor, that expects only
          # options has as argument (refresh: true | false), but provides
          # a block for initially setting the value
          #
          def attr_memoized(*attributes)
            attributes  = [attributes] unless attributes.is_a?(Array)
            block       = attributes.pop if attributes.last.is_a?(Proc)
            method_name = attributes.pop if attributes.last.is_a?(Symbol) && !block

            attributes.each do |attribute|
              define_method(attribute) do |refresh: false|
                assign_and_return(attribute, refresh: refresh) do
                  method_name ? self.send(method_name) : instance_exec(&block)
                end
              end
            end
          end
        end
        # instance method: uses the class mutex to create an instance
        # mutex, and then uses the instance mutex to wrap instance's
        # state
        def mutex
          return @mutex if @mutex
          self.class.mutex.synchronize { @mutex ||= Mutex.new }
        end
      end
    end
  end

  #
  # @param [Symbol] attribute  —  name of the attribute
  # @param [Boolean] refresh   —  if true, forces refetching of the value
  #                               by calling the block given.
  def assign_and_return(attribute, refresh: false)
    raise ArgumentError, 'method must be called with a block' unless block_given?

    # Allow arguments to be a simple attribute name as a symbol
    attribute = "@#{attribute}".to_sym unless attribute.to_s.start_with?('@')

    # quickly return if we already have the value, and refresh was not
    # set to true
    var = self.instance_variable_get(attribute)
    return var if var && !refresh

    # this is the part that can get gobbled up if multiple threads are
    # calling it, so wrap it in mutex.
    self.mutex.synchronize do
      # do second check, in case this was defined during a race condition
      var = self.instance_variable_get(attribute)
      return var if var && !refresh
      yield(self).tap do |result|
        self.instance_variable_set(attribute, result)
      end
    end
  end
end
