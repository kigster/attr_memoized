require 'spec_helper'

srand
require 'attr_memoized'

class RandomNumberGenerator
  include AttrMemoized
  attr_memoized :random1,
                :random2,
                :random3, -> { rand(2 ** 64) }
  attr_memoized :random, -> { rand(10) }, writer: false
  attr_memoized :seed, -> { Time.now.to_i % 57 }
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
end
