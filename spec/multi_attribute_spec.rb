# frozen_string_literal: true

require 'spec_helper'

srand
require 'attr_memoized'
require 'bigdecimal/math'

class RandomNumberGenerator
  include AttrMemoized
  attr_memoized :seed, -> { Time.now.to_i % 57 }

  attr_memoized_reader :random1,
                       :random2,
                       :random3, -> { rand(2**64) }

  attr_memoized_reader :random, -> { rand(10) }

  attr_memoized_reader :pi, :compute_pi # call a class method when accessed
  attr_memoized_reader :pi25, :compute_pi, digits: 25 # pass an argument to a lazy-init method

  # Returns PI as a string with a custom number of digits.
  #
  # @param [Integer] digits number of digits to generate PI up to, default is 15.
  def compute_pi(digits: 15)
    precision = digits
    result    = BigMath.PI(precision)
    result    = result.truncate(precision).to_s
    result    = result[2..-1] # Remove '0.'
    result    = result.split('e').first # Remove 'e1'
    result.insert(1, '.')
  end
end

RSpec.describe RandomNumberGenerator do
  subject(:rng) { RandomNumberGenerator.new }

  # Once generated, it should be
  its(:random1) { should_not be_nil }
  its(:random2) { should_not be_nil }
  its(:random3) { should_not be_nil }

  its(:random1) { should eq(rng.random1) }
  its(:random2) { should eq(rng.random2) }
  its(:random3) { should eq(rng.random3) }

  its(:random1) { should_not eq(rng.random2) }
  its(:random1) { should_not eq(rng.random3) }
  its(:random2) { should_not eq(rng.random3) }

  its(:random) { should_not be_nil }
  its(:seed) { should_not be_nil }
  its(:random) { should eq subject.random }
  its(:seed) { should eq subject.seed }

  its(:pi) { should_not be_nil }
  its(:pi) { should eq "3.141592653589793" }

  its(:pi25) { should eq "3.1415926535897932384626433" }
end
