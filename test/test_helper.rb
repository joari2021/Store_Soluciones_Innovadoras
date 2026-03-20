ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'

# Rails 7.1 defines Rails::LineFiltering#run with two arguments, but Minitest 6
# calls it with an additional argument. Accept splat args to stay compatible.
module Rails
  module LineFiltering
    def run(*args)
      return super if args.length == 3

      reporter = args[0]
      options = args[1] || {}
      options = options.merge(filter: Rails::TestUnit::Runner.compose_filter(self, options[:filter]))
      super(reporter, options)
    end
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
