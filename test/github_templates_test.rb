# frozen_string_literal: true

require "test_helper"
require "yaml"

class GitHubTemplatesTest < Minitest::Test
  def test_every_issue_starts_from_a_form
    assert_same false, template("config.yml").fetch("blank_issues_enabled")
  end

  def test_security_reports_are_sent_to_the_private_reporting_policy
    links = template("config.yml").fetch("contact_links").map { |link| link.fetch("url") }

    assert_equal ["https://github.com/hvpaiva/rich-ri/blob/main/SECURITY.md"], links
    assert_path_exists File.join(TestSupport::ROOT, "SECURITY.md")
  end

  def test_fields_have_unique_identifiers_and_labels
    forms.each_value do |form|
      fields = form.fetch("body")

      assert_equal fields.length, fields.map { |field| field.fetch("id") }.uniq.length
      assert_equal fields.length, fields.map { |field| field.fetch("attributes").fetch("label") }.uniq.length
    end
  end

  def test_every_rich_ri_option_a_form_shows_is_an_option_of_rich_ri
    shown = form_text.scan(/rich-ri((?: --?[\w=-]+)+)/).flatten.flat_map(&:split).map { |option| option[/\A[^=]+/] }

    refute_empty shown
    assert_empty shown - rich_ri_options
  end

  def test_every_variable_a_form_asks_for_is_one_the_help_names
    help = RichRI::Options.new.parser.to_s
    variables = form_text.scan(/`([A-Z][A-Z0-9_]*)`/).flatten

    assert_includes variables, "RI_PAGER"
    assert_empty(variables.reject { |name| help.match?(/(?<![\w$])#{name}(?!\w)/) })
  end

  private

  def form_text = forms.keys.map { |name| File.read(File.join(TestSupport::ROOT, ".github/ISSUE_TEMPLATE", name)) }.join

  def rich_ri_options
    RichRI::Options.new.parser.to_a.grep(/\A\s+-/).flat_map do |line|
      line.strip.split(/\s{2,}/).first.scan(/--(\[no-\])?([\w-]+)/).flat_map do |negatable, name|
        negatable ? ["--#{name}", "--no-#{name}"] : ["--#{name}"]
      end
    end
  end

  def template(name) = YAML.load_file(File.join(TestSupport::ROOT, ".github/ISSUE_TEMPLATE", name))

  def forms = %w[bug.yml feature.yml].to_h { |name| [name, template(name)] }
end
