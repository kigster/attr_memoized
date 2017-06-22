require 'spec_helper'

RSpec.describe AttrMemoized do
  it 'has a version number' do
    expect(AttrMemoized::VERSION).not_to be nil
  end

  before { allow(store).to receive(:initializing) }
  # Validate the gem using the PetStore example.

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

  describe 'variable assignment' do
    before { store.instance_variable_set(:@turtles, nil) }

    it_should_behave_like :thread_safe_attribute,
                          :turtles, # attribute
                          :grow_turtles # actual method to loa value

    context '#turtles' do
      it 'should not be equal to the new turtles before assignment' do
        expect(store.turtles).to_not be_nil
      end

      context '#turtles=' do
        let(:new_turtles) { [PetStore::Turtle.new('Benji'), PetStore::Turtle.new('Franklin')] }
        before { store.turtles }

        it 'should properly assign the value' do
          store.turtles = new_turtles
          expect(store.turtles).to eq(new_turtles)
        end
      end

    end

    context '#sheep=' do
      before do
        expect(store.sheep.size).to eq(1)
        expect(store.sheep.first.color).to eq(:black)
      end
      it 'should raise NameError when called' do
        expect { store.sheep = nil }.to raise_error(NameError)
      end
    end
  end
end
