require 'bundler/setup'
require 'simplecov'
require 'rspec'
require 'rspec/its'

SimpleCov.start do
  add_filter '/spec/'
end

require 'attr_memoized'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

require 'support/pet_store'
require 'support/shared_examples'
