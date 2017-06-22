require 'spec_helper'

def define_in_two_threads(attribute)
  t1 = Thread.new { store.send(attribute) }
  t2 = Thread.new { store.send(attribute) }

  r1 = t1.value
  r2 = t2.value

  return r1, r2
end

# Define #store in the outer context.

RSpec.shared_examples_for :thread_safe_attribute \
    do |attribute, actual_method, result_evaluator, expected_result_value|

  it 'should correctly initialize each member once' do
    allow(store).to receive(:initializing).with(actual_method)

    r1, r2 = define_in_two_threads(attribute)

    # they should literally be the same object
    expect(r1).to eq(r2)
    expect(r1.object_id).to eq(r2.object_id)
    expect(result_evaluator[r1]).to eq(expected_result_value) if result_evaluator

    expect(store).not_to receive(actual_method)
    expect(store.send(attribute)).to eq(r1)
  end

  it 'should correctly initialize each member once' do
    allow(store).to receive(:initializing).with(actual_method)

    r1, r2 = define_in_two_threads(attribute)

    # they should literally be the same object
    expect(r1).to eq(r2)
    expect(r1.object_id).to eq(r2.object_id)
    expect(result_evaluator[r1]).to eq(expected_result_value) if result_evaluator

    expect(store.send(attribute).object_id).to eq(r1.object_id)
    expect(store.send(attribute, refresh: true).object_id).not_to eq(r1.object_id)
  end


end
