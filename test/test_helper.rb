ENV["RAILS_ENV"] ||= "test"
ENV["RAF_TRUST_NETWORK"] ||= "1" # controller auth fails closed (see ApplicationController)
require_relative "../config/environment"
require "rails/test_help"

# minitest 6 moved Object#stub to a separate gem; this is the classic
# implementation (swap a method for the block's duration), enough for us.
class Object
  def stub(name, val_or_callable)
    stashed = "__stubbed_#{name}"
    metaclass = singleton_class
    metaclass.send :alias_method, stashed, name
    metaclass.send :define_method, name do |*args, **kwargs, &blk|
      val_or_callable.respond_to?(:call) ? val_or_callable.call(*args, **kwargs, &blk) : val_or_callable
    end
    yield self
  ensure
    metaclass.send :undef_method, name
    metaclass.send :alias_method, name, stashed
    metaclass.send :undef_method, stashed
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
