[![Build Status](https://travis-ci.org/kigster/attr_memoized.svg?branch=master)](https://travis-ci.org/kigster/attr_memoized)
[![Code Climate](https://codeclimate.com/github/kigster/attr_memoized/badges/gpa.svg)](https://codeclimate.com/github/kigster/attr_memoized)
[![Test Coverage](https://codeclimate.com/github/kigster/attr_memoized/badges/coverage.svg)](https://codeclimate.com/github/kigster/attr_memoized/coverage)
[![Issue Count](https://codeclimate.com/github/kigster/attr_memoized/badges/issue_count.svg)](https://codeclimate.com/github/kigster/attr_memoized)

# AttrMemoized

This is a simple, and yet rather useful **memoization** library, with a specific goal of being **thread-safe** during lazy-loading of attributes. Class method `attr_memoized` automatically generates thread-safe reader and writer methods, particularly ensuring thread-safe delayed initialization.

The primary and recommended way to use this library is to use it like a thread-safe lazy loader which essentially _caches_ heavy **attributes** in a multi-threaded environment. Once the attribute is initialized and returned for the very first time,  any subsequent calls are returned instantly, without the expensive `#synchronize`. 

The library expects that you treat the attributes, once you fetch them, **as read-only constants**. However, you can _re-assign_ an attribute after it's aleady been initialized, and such assignment will be performed with proper synchronization. You can also, optionally, disable the attribute writer generation by passing `writer: false` option.

The gems solves race condition in lazy-initialization by creating thread-safe wrappers around (possibly) thread-unsafe operations.

## Complete Example

Below we have a `Configuration` class that has several attributes that are all lazy loaded.

```ruby
require 'redis'
require 'attr_memoized'
# Save config to Redis
r = Redis.new
#=> #<Redis:0x007fbd8d3a4308>
r.set('config_file', '{ "host": "127.0.0.1" }')
#=> OK
r.set('another_file', '{ "host": "google.com" }')
#=> OK
r.get('config_file') #=> { "host": "127.0.0.1" }

module Concurrent
  class RedisConfig
    include AttrMemoized

    attr_memoized :contents, -> { redis.get(redis_key) } 
    attr_memoized :redis,  -> { Redis.new }   
    attr_memoized :redis_key, -> { 'config_file' }
  
    def reload_config!(new_key)
      with_lock do 
        self.redis_key = new_key
        contents(reload: true)
      end
    end
  end
end

@config = Concurrent::RedisConfig.new
@config.contents
#=> { "host": "127.0.0.1" }
@config.reload_config!('another_file')
#=> { "host": "google.com" }
@config.contents
#=> { "host": "google.com" }
```    


### The Problem

One of the issues with memoization in multi-threaded environment is that it may lead to unexpected or undefined behavior, due to the situation known as a _race condition_.

Consider a simple example below:

```ruby
class Account
  def self.owner
    # Slow expensive query
    @owner ||= ActiveRecord::Base.execute('select ...')
  end
end
# Let's be dangerous:
[   Thread.new { Account.owner }, 
    Thread.new { Account.owner } ].map(&:join)
```

As a reminder — Ruby evalues `a||=b` as `a || a=b`, which means that the assignment won't happen if `a` is falsey, ie. `false` or `nil`. In this example, if the `#owner` is not synchronized, both threads will execute the expensive query, and only the result of the query executed by the second thread will be saved in `@owner`, even though by that time it will already have a value assigned by the first thread that finished earlier.

Most memoization gems out there that the author reviewed, did not seem to concern themselves witn thread safety, which may be OK under wide ranging situations, particularly if the objects are not shared across threads. 

But in multi-threaded applications it's important to protect initializers of expensive resources, which is exactly what this library attempts to accomplish.


## Usage

Gem's primary module, when included, decorates the receiver with several useful
methods:

  * New class method `#attr_memoized` is added, with the following syntax:

```ruby
attr_memoized :attribute_name, ..., -> { block returning a value }
```

  * Convenience method `#with_lock` should be used to wrap any state change to the class to guard against modification by other threads. It will only use `mutex.synchronize` once per thread, thus avoiding a common source of deadlocks.
     
  * Class level `#mutex` method, as well as instance. Each class gets their own mutex, as well each instance. 

  * the block in the definition above is called via #instance_exec on the object (instance of a class) and has, therefore, access to all private methods. If the value is a symbol, it is expected to be a method name, of an instance method with no arguments.
     
  * multiple attribute names are allowed in the `#attr_memoized`, and they will be assigned the result of the block whenever lazy-loaded.


Typically, however, you would use `#attr_memoized` with just one attribute at a time, unless you want to have several version of the same variable.
     
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
