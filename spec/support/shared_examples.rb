require 'spec_helper'

def define_in_two_threads(attribute)
  t1 = Thread.new { store.send(attribute) }
  t2 = Thread.new { store.send(attribute) }

  r1 = t1.value
  r2 = t2.value

  return r1, r2
end

# Define #store in the outer context.

RSpec.shared_examples_for :thread_safe_attribute do \
  | \
  attribute:,
  load_method:,
  result_transformer: nil,
  expected_value: nil,
  ignore_reload: false|

  it 'should correctly initialize each member once' do
    allow(store).to receive(:initializing).with(load_method)

    r1, r2 = define_in_two_threads(attribute)

    # they should literally be the same object
    expect(r1).to_not be_nil
    expect(r2).to_not be_nil

    expect(r1).to eq(r2)
    expect(r1.object_id).to eq(r2.object_id)

    expect(result_transformer[r1]).to eq(expected_value) if result_transformer

    expect(store).not_to receive(load_method) if load_method && ignore_reload

    expect(store.send(attribute)).to eq(r1)
    expect(store.send(attribute).object_id).to eq(r1.object_id)
    expect(store.send(attribute, reload: true).object_id).not_to eq(r1.object_id) \
      unless ignore_reload
  end



end
