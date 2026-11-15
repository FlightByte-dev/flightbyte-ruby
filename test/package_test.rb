# frozen_string_literal: true

require "test_helper"

class PackageTest < Minitest::Test
  SPEC = Dir.chdir(FlightByteTest::ROOT) { Gem::Specification.load("flightbyte.gemspec") }

  def test_has_the_same_version_as_the_code
    assert_equal FlightByte::VERSION, SPEC.version.to_s
    assert_match(/\A\d+\.\d+\.\d+\z/, FlightByte::VERSION)
  end

  def test_has_no_runtime_dependencies
    assert_empty SPEC.runtime_dependencies
  end

  def test_ships_the_code_the_signatures_and_the_docs_only
    allowed = ->(path) { path.start_with?("lib/", "sig/") || %w[README.md CHANGELOG.md LICENSE].include?(path) }

    assert_empty SPEC.files.reject(&allowed)
    assert_includes SPEC.files, "lib/flightbyte.rb"
    assert_includes SPEC.files, "LICENSE"
  end

  def test_loads_every_file_it_ships
    loaded = $LOADED_FEATURES.map { |path| File.expand_path(path) }
    shipped = SPEC.files.grep(/\.rb\z/).map { |path| File.join(FlightByteTest::ROOT, path) }

    assert_empty shipped - loaded
  end

  def test_asks_for_ruby_3_1_and_describes_itself
    assert_equal Gem::Requirement.new(">= 3.1"), SPEC.required_ruby_version
    assert_equal ["MIT"], SPEC.licenses
    assert_equal "https://flightbyte.dev", SPEC.homepage
    assert_equal "true", SPEC.metadata["rubygems_mfa_required"]
    %w[documentation_uri source_code_uri bug_tracker_uri changelog_uri].each do |key|
      assert_match(%r{\Ahttps://}, SPEC.metadata.fetch(key))
    end
  end

  def test_has_a_changelog_section_for_the_version
    changelog = File.read(File.join(FlightByteTest::ROOT, "CHANGELOG.md"), encoding: "UTF-8")

    assert_includes changelog.lines.map(&:chomp), "## #{FlightByte::VERSION}"
  end
end
