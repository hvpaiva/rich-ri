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

  private

  def template(name) = YAML.load_file(File.join(TestSupport::ROOT, ".github/ISSUE_TEMPLATE", name))

  def forms = %w[bug.yml feature.yml].to_h { |name| [name, template(name)] }
end
