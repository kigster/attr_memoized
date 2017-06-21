require 'spec_helper'

RSpec.describe AttrMemoized do
  it 'has a version number' do
    expect(AttrMemoized::VERSION).not_to be nil
  end

  class Pet < Struct.new(:name)
  end
  class Dog < Pet
  end
  class Cat < Pet
  end
  class Turtle < Pet
  end

  class PetStore
    include AttrMemoized

    attr_memoized :turtles, -> { grow_turtles }

    # A contrived example, here we have two values :cats and :dogs memoized
    # to two separate calls to method :pet_creator.
    #
    # Because variables are initialized lazily, the order will depend on
    # the usage.
    attr_memoized :cats, :dogs, :pet_creator

    attr_reader :turtle_counter, :pet_counter

    TURTLE_NAMES = %i(Scary Horrible Monstrocity Bloodthirsty)

    def initialize
      @turtle_counter = 0
      @pet_counter    = 0
    end

    def grow_turtles
      @turtle_counter += 1
      sleep 0.5 # turtles grow slow or something.
      initializing(:grow_turtles)
      TURTLE_NAMES.map { |name| Turtle.new(name) }
    end

    def pet_creator
      sleep 0.1
      @pet_counter += 1
      initializing(:pet_creator)
      @pet_counter.odd? ? Cat.new('tootsie') : Dog.new('sniffy')
    end

    def initializing(*)
      puts 'I am never actually called'
    end
  end

  before { allow(store).to receive(:initializing) }

  shared_examples_for :thread_safe_attribute \
    do |attribute, actual_method,  result_evaluator,  expected_result_value|

    it 'should correctly initialize each member once' do
      expect(store).to receive(:initializing).with(actual_method).once

      t1 = Thread.new { store.send(attribute) }
      t2 = Thread.new { store.send(attribute) }

      r1 = t1.value
      r2 = t2.value

      # they should literally be the same object
      expect(r1).to eq(r2)
      expect(r1.object_id).to eq(r2.object_id)

      expect(store).not_to receive(actual_method)
      expect(store.send(attribute)).to eq(r1)

      expect(result_evaluator[r1]).to eq(expected_result_value) if result_evaluator
    end
  end

  subject(:store) { PetStore.new }
  describe :cats do
    it_should_behave_like :thread_safe_attribute,
                          :cats, # attribute
                          :pet_creator, # actual method to load value
                          ->(result) { result.name },
                          'tootsie'
  end
  describe :dogs do
    before { store.cats }
    it_should_behave_like :thread_safe_attribute,
                          :dogs, # attribute
                          :pet_creator, # actual method to load value
                          ->(result) { result.name },
                          'sniffy'
  end
  describe :turtles do
    before { store.cats; store.dogs }
    it_should_behave_like :thread_safe_attribute,
                          :turtles, # attribute
                          :grow_turtles # actual method to loa value
  end
end
