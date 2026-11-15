# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "lib" << "test"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = true
end

begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new(:rubocop)
rescue LoadError
  desc "Run RuboCop (not installed)"
  task(:rubocop) { abort "RuboCop is not installed: run bundle install." }
end

desc "Validate the type signatures in sig/"
task :rbs do
  sh "rbs", "-r", "date", "-I", "sig", "validate"
end

desc "Build the gem into pkg/"
task :build do
  mkdir_p "pkg"
  sh "gem build flightbyte.gemspec --output pkg/flightbyte-#{Gem::Specification.load("flightbyte.gemspec").version}.gem"
end

desc "Refresh spec/openapi.json from the API (or URL=...), then run the tests against it"
task :sync_openapi do
  ruby "tool/sync_openapi.rb", *ENV.fetch("URL", nil).to_s.split
end

desc "Run RuboCop, the signature check and the tests"
task check: %i[rubocop rbs test]

task default: :check
