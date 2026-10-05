# frozen_string_literal: true

require "test_helper"
require "command_helper"

class PagerSettingsTest < Minitest::Test
  include CommandSupport

  def test_pager_commands_take_precedence_in_the_documented_order
    with_config({ "pager" => "from-file" }) do |path|
      layers = { "RI" => "--pager-command=from-ri", "RICH_RI_CONFIG" => path, "RI_PAGER" => "from-environment" }
      { [["--pager-command=from-command-line"], layers] => "from-command-line",
        [[], layers] => "from-environment",
        [[], layers.except("RI_PAGER")] => "from-file",
        [["--no-config"], layers.except("RI_PAGER")] => "from-ri" }.each do |(args, env), pager|
        out, err, status = cli(*args, "--show-config", docs: false, env: env.merge("PAGER" => "from-pager"))

        assert_predicate status, :success?, err
        assert_equal pager, Psych.safe_load(out).fetch("pager")
      end
    end
  end

  def test_pager_settings_reach_only_the_pager_not_the_commands_own_environment
    observer = <<~RUBY
      require "rich_ri"
      RichRI::Driver.prepend(Module.new do
        def run
          warn ENV.values_at("RI_PAGER", "LESS").inspect
          super
        end
      end)
    RUBY
    out, err, status = with_planted(observer, env: { "RI_PAGER" => "original", "LESS" => "-i" }) do |env|
      cli("--pager-command=cat", "--list", env: env)
    end

    assert_predicate status, :success?, err
    assert_equal "RichRIExample\nRichRIExample::Nested\n", out
    assert_equal %(["original", "-i"]\n), err
  end
end
