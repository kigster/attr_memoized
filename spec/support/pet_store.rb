require 'attr_memoized'
class PetStore

  class Pet < Struct.new(:name)
  end
  class Dog < Pet
  end
  class Cat < Pet
  end
  class Turtle < Pet
  end

  include AttrMemoized

  # In this example, we have a dependency, so it's important
  # the thread does not deadlock when instantiating both
  attr_memoized :turtles, -> { grow_turtles }
  attr_memoized :lead_turtle, -> { turtles.first }

  attr_memoized :sheep, -> { Array[Struct.new(:color).new(:black)] }, writer: false

  # A contrived example, here we have two values :cats and :dogs memoized
  # to two separate calls to method :pet_creator.
  #
  # Because variables are initialized lazily, the order will depend on
  # the usage.
  attr_memoized :cats, :dogs, :pet_creator

  attr_reader :turtle_counter, :pet_counter

  TURTLE_NAMES = %i(Scary Horrible Monstrosity Bloodthirsty)

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

  def load_lead_turtle
    turtles.first
  end

  # marker method used in specs
  def initializing(*)
    # nada
  end
end
