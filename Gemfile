# frozen_string_literal: true

source "https://rubygems.org"

# The gem itself has no dependencies; everything here is for developing it.
gemspec

group :development do
  gem "minitest", ">= 5.20"
  gem "rack", ">= 2.2" # only to check RackApp with Rack::Lint
  gem "rake", ">= 13.0"
  gem "rbs", ">= 3.0", require: false # checks sig/ with rake rbs
  gem "rubocop", ">= 1.76", require: false # Naming/PredicateMethod
  gem "rubocop-minitest", require: false
  gem "rubocop-rake", require: false
end
