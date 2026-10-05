# frozen_string_literal: true

require "test_helper"
require "yaml"

class GitHubTemplatesTest < Minitest::Test
  def test_every_issue_starts_from_a_form_and_security_reports_stay_private
    config = template("config.yml")

    assert_same false, config.fetch("blank_issues_enabled")
    assert_equal(["https://github.com/hvpaiva/rich-ri/blob/main/SECURITY.md"],
                 config.fetch("contact_links").map { |link| link.fetch("url") })
  end

  def test_a_bug_report_requires_what_reproducing_it_takes
    fields = forms.fetch("bug.yml").fetch("body")
    required = fields.select { |field| field.dig("validations", "required") }.map { |field| field.fetch("id") }

    assert_equal %w[what-happened expected reproduction version ruby environment], required
    assert_includes fields.map { |field| field.fetch("id") }, "configuration"
  end

  def test_fields_have_unique_identifiers_and_labels
    forms.each_value do |form|
      fields = form.fetch("body")

      assert_equal fields.length, fields.map { |field| field.fetch("id") }.uniq.length
      assert_equal fields.length, fields.map { |field| field.fetch("attributes").fetch("label") }.uniq.length
    end
  end

  private

  def template(name) = YAML.load_file(File.join(TestSupport::ROOT, ".github/ISSUE_TEMPLATE", name))

  def forms = %w[bug.yml feature.yml].to_h { |name| [name, template(name)] }
end
