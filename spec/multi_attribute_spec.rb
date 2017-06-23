require 'spec_helper'

srand
require 'attr_memoized'

class RandomNumberGenerator
  include AttrMemoized
  attr_memoized :random1,
                :random2,
                :random3, -> { rand(2**64) }
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
end
