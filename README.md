[![Build Status](https://travis-ci.org/kigster/attr_memoized.svg?branch=master)](https://travis-ci.org/kigster/attr_memoized)
[![Code Climate](https://codeclimate.com/github/kigster/attr_memoized/badges/gpa.svg)](https://codeclimate.com/github/kigster/attr_memoized)
[![Test Coverage](https://codeclimate.com/github/kigster/attr_memoized/badges/coverage.svg)](https://codeclimate.com/github/kigster/attr_memoized/coverage)
[![Issue Count](https://codeclimate.com/github/kigster/attr_memoized/badges/issue_count.svg)](https://codeclimate.com/github/kigster/attr_memoized)

# AttrMemoized

This is a simple, and yet rather useful **memoization** library, with a specific goal of being also **thread-safe.**

> NOTE: the most useful and recommended way to use this library is to memoize **read-only attributes** in a multi-threaded environment. The attribues should almost be constants: the type you initialize once, and ever again.  

One of the biggest issues with memoization is that in multi-threaded environment memoization often lead to unexpected or undefined results, due to a situation known as a _race condition_.

Consider a simple example below:

```ruby
class Account
  def owner(id)
    # Slow query, takes ~ 50 ms
    @owner ||= ActiveRecord::Base.execute("select ... ", id: id) 
  end
end
```

This can be a problem. 

Ruby evalues `a||=b` as `a || a=b`, which means that the assignment won't happen if `a` is falsey, ie. `false` or `nil`. If two theads, happen to access this method nearly at nearly the same time, both threads will determine that `@owner` is nil, and then both will execute an expensive operation. First assignment is immediately overwritten by the assignment in the second thread. If the operation is idempotent (ie, does not change state when run multiple times) this ultimately may be OK, but if not, then we have a real problem.

Most memoization gems out there do not concern themselves witn thread safety, which may be OK under some situations. In others, where multiple threads are used, in particularly over a period of time, then it might be nice to have a convenient wrapper optimized for performance, and avoiding additional calls after the first call returns...

The gems solves this by creating a thread-safe wrappers around possibly thread-unsafe methods.  Here is the most basic example:

```ruby
require 'aws-sdk'
require 'attr_memoized'
# eg: a hypothetical wrapper around AWS Kinesis API:
class AwsKinesisWrapper
  include AttrMemoized
  attr_memoized :client, -> { create_client }, writer: false 
  attr_memoized :stream, -> { client.describe_stream(stream_name: 'lotus') }
  def create_client
    Aws::Kinesis::Client.new(region: 'us-west-2')
  end
end
```

Note, that by default `attr_memoized` will create both `#attribute` and `#attribute=(value)` methods that are thread safe. While the writer is not something we expect to be used often, the thinkning was, might as well provide a thread-safe attribute setter just in case it is used. But the primary use-case for using this library is **lazy-initialization in a thread-safe way**.

## Usage

Gem's primary module, when included, decorates the receiver with several useful
methods:

  * Both class and any object instance receives the `#mutex` methods, that can be used to guard any shared resources. Each class gets their own class mutex, and each instance gets it's own separate mutex, separate from the class's mutex:

```ruby
# eg:
class ThreadSafe
  include AttrMemoized
  
  mutex.synchronize do 
    # imporant class operation
  end
  
  def download(file)
    mutex.synchronize do
      @file ||= file
    end
    
    mutex == self.class.mutex # => false
  end
end

```    
     
  * New class method `#attr_memoized` is added, with the following syntax:

```ruby
attr_memoized :attribute_name, ..., -> { block returning a value }
```

  * the block in the definition above is called via #instance_exec on the
    object (instance of a class) and has, therefore, access to all private
    methods. If the value is a symbol, it is expected to be a method name, 
    of an instance method with no arguments.
     
  * multiple attribute names are allowed in the `#attr_memoized`, and they
    will be assigned the result of the block whenever lazy-loaded.

Typically, however, you would use `#attr_memoized` with just one attribute at
a time, unless you want to have several version of the same variable (which 
is shown in the following example, albeit a contrived one).
     

```ruby
require 'attr_memoized'

class RandomNumbers
  include AttrMemoized
  # this uses a Proc syntax, which is eva
  attr_memoized :number1, :number2, -> { small_random_number }
  attr_memoized :big, :generate_big_number
  
  def generate_big_number
    rand(2**64)
  end
  
  def small_random_number
    rand(2**10)
  end
end

@rn = RandomNumbers.new
@rn.instance_variable_get(:@number1) # => nil
@rn.instance_variable_get(:@number2) # => nil

Thread.new do 
  @rn.number1                          # => 461
  # and it's memoized now:
  @rn.number1                          # => 461
end

Thread.new do 
  @rn.number2                          # => 556
end

@rn.number1 			# => 461
@rn.number2 			# => 556
@rn.big       		# => 10569575038899804255
```



## Installation

Add this line to your application's Gemfile:

```ruby
gem 'attr_memoized'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install attr_memoized


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/kigster/attr_memoized](https://github.com/kigster/attr_memoized).

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
