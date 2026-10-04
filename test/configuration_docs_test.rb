# frozen_string_literal: true

require "test_helper"
require "yaml"
require_relative "../rakelib/manual"

class ConfigurationDocsTest < Minitest::Test
  def test_annotated_example_covers_the_supported_schema_and_roles
    example = YAML.safe_load(read("docs/config.example.yml"))
    defaults = RichRI::Options.new.parse([], defaults: "", configuration: false).settings

    assert_equal defaults.except("width", "styles"), example.except("width", "styles")
    assert_equal RichRI::Configuration::KEYS.sort, example.keys.sort
    assert_equal RichRI::Configuration::SOURCES.sort, example.fetch("sources").keys.sort
    assert_equal RichRI::Theme::ROLES.map(&:to_s).sort, example.fetch("styles").keys.sort
  end

  def test_documented_yaml_examples_are_accepted_by_the_executable
    examples = [read("docs/config.example.yml")]
    %w[README.md docs/configuration.md].each do |path|
      examples.concat(read(path).scan(/```yaml\n(.*?)```/m).flatten)
    end
    Dir.mktmpdir do |directory|
      examples.each_with_index do |source, index|
        path = File.join(directory, "example-#{index}.yml")
        File.write(path, source)
        out, err, status = cli("--config", path, "--show-config", docs: false)

        assert_predicate status, :success?, "Example #{index}: #{err}"
        assert_equal RichRI::Configuration::KEYS.sort, YAML.safe_load(out).keys.sort
      end
    end
  end

  def test_reference_covers_every_configuration_key_and_style_role
    reference = read("docs/configuration.md")
    names = RichRI::Configuration::KEYS + RichRI::Theme::ROLES.map(&:to_s)

    names.uniq.each { |name| assert_includes reference, "| `#{name}` |" }
  end

  def test_reference_and_manual_cover_configuration_environment
    names = RichRI::Configuration::ENVIRONMENT.keys +
            %w[RICH_RI_CONFIG RICH_RI_STYLE_<ROLE> RI_PAGER BAT_THEME XDG_CONFIG_HOME COLORTERM]
    [read("docs/configuration.md"), Manual.render].each do |document|
      names.each { |name| assert_includes document, name }
    end
  end

  private

  def read(path)
    File.read(File.join(TestSupport::ROOT, path))
  end
end
