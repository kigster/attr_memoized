[![Build Status](https://travis-ci.org/kigster/attr_memoized.svg?branch=master)](https://travis-ci.org/kigster/attr_memoized)
[![Code Climate](https://codeclimate.com/github/kigster/attr_memoized/badges/gpa.svg)](https://codeclimate.com/github/kigster/attr_memoized)
[![Test Coverage](https://codeclimate.com/github/kigster/attr_memoized/badges/coverage.svg)](https://codeclimate.com/github/kigster/attr_memoized/coverage)
[![Issue Count](https://codeclimate.com/github/kigster/attr_memoized/badges/issue_count.svg)](https://codeclimate.com/github/kigster/attr_memoized)

# AttrMemoized

This is a simple, and yet rather useful **memoization** library, with a specific goal of being **thread-safe** during lazy-loading of attributes. Class method `attr_memoized` automatically generates attribute reader and attribute writer methods. The reader performs a thread-safe lazy-initialization of each attribute. The writer performs a thread-safe assignment. You can disable writer method generation by passing `writer: false` option to `attr_memoized` method.

Any `attr_memoized` attribute may depend on any number of regular attributes or other `attr_memoized` attributes.

This gems provides a shorthand syntax for defining lazy-initialized variables as "one-liners", while additionally providing thread-safety guarantees around lazy-initilization of attributes, or attribute assignments.

#### Caveat

Note, that if the initialization or assignment returns a "falsey" result (ie, `false` or `nil`), then the attribute will attempt to be re-initialized every time its "reader" method is called. This is not a bug. We treat falsey value as uninitialized by design.

## Complete Example

Below we have a `Configuration` class that has several attributes that are all lazy loaded.

```ruby
require 'redis'
# Save config to Redis
r = Redis.new
#=> #<Redis:0x007fbd8d3a4308>
r.set('config_file', '{ "host": "127.0.0.1" }')
#=> OK
r.set('another_file', '{ "host": "google.com" }')
#=> OK
r.get('config_file') #=> { "host": "127.0.0.1" }

require 'attr_memoized'
module Concurrent
  class RedisConfig
    include AttrMemoized
    # Now there is an instance and a class methods +#mutex+ are defined.
    # We also have an instance method +with_lock+, and a class method 
    # +attr_memoized+
    attr_memoized :contents, -> { redis.get(redis_key) } 
    attr_memoized :redis,  -> { Redis.new }   
    attr_memoized :redis_key, -> { 'config_file' }
  
    def reload_config!(new_key)
      # +with_lock+ method if offered in place of +synchronize+
      # to avoid double-locking within the same thread.
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

One of the issues with memoization in multi-threaded environment is that it may lead to unexpected or undefined behavior, due to the situation known as a [_race condition_](https://stackoverflow.com/questions/34510/what-is-a-race-condition).

Consider the following example:

```ruby
class Account
  def self.owner
    # Slow expensive query
    @owner ||= ActiveRecord::Base.execute('select ...').first
  end
end
# Let's be dangerous:
[   Thread.new { Account.owner }, 
    Thread.new { Account.owner } ].map(&:join)
```

Ruby evaluates `a||=b` as `a || a=b`, which means that the assignment above won't happen if `a` is "falsey", ie. `false` or `nil`. If the method `self.owner` is not synchronized, then both threads will execute the expensive query, and only the result of the query executed by the second thread will be saved in `@owner`, even though by that time it will already have a value assigned by the first thread, that by that time had already completed.

Most memoization gems out there, among those that the author had reviewed, did not seem to be concerned with thread safety, which is actually OK under wide ranging situations, particularly if the objects are not meant to be shared across threads. 

But in multi-threaded applications it's important to protect initializers of expensive resources, which is exactly what this library attempts to accomplish.


## Usage

`AttrMemoized` — the gem's primary module, when included, decorates the receiver with several useful
methods:

  * Pre-initialized class method `#mutex`. Each class that includes `AttrMemoized` gets their own mutex.
   
  * Pre-initialized instance method `#mutex`. Each instance of the class gets it's own dedicated mutex.

  * Convenience method `#with_lock` is provided in place of `#mutex.synhronize` and should be used to wrap any state changes to the class in order to guard against concurrent modification by other threads. It will only use `mutex.synchronize` once per thread, to avoid self-deadlocking.
     
  * New class method `#attr_memoized` is added, with the following syntax:

```ruby
attr_memoized :attribute, [ :attribute, ...], -> { block returning a value } # Proc
attr_memoized :attribute, [ :attribute, ...], :instance_method               # symbol
attr_memoized :attribute, [ :attribute, ...], SomeClass.method(:method_name) # Method instance
```

  * In the above definitions: 
    * If a `Proc` is provided as an initializer, it will be called via `#instance_exec` method on the instance and, therefore, can access any public or private method of the instance without the need for `self.` receiver. 

    * If the initializer is a `Symbol`, it is expected to be an instance method name, of a method that takes no arguments.
 
    * Finally, any `Method` instance can also be used.

    * Note, that multiple attribute names can be passed to `#attr_memoized`, and they will be lazy-loaded in the order of access and independently of each other. If the block always returns the same exactly value, then the list may be viewed as aliases. But if the block returns a new value each time its called, then each attribute will be initialized with a different value, eg:

```ruby
srand
require 'attr_memoized'
class RandomNumberGenerator
  include AttrMemoized
  attr_memoized :random1,
                :random2,
                :random3, -> { rand(2**64) }
end

rng = RandomNumberGenerator.new
# each is initialized as it's called, and so they 
# are all different:
rng.random1 #=> 1304594275874777789
rng.random2 #=> 12671375021040220422
rng.random3 #=> 16656281832060271071

# second time, they are all already memoized:
rng.random1 #=> 1304594275874777789
rng.random2 #=> 12671375021040220422
rng.random3 #=> 16656281832060271071
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
