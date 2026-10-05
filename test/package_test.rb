# frozen_string_literal: true

require "test_helper"
require "program_support"
require "rubygems/package"

class PackageTest < Minitest::Test
  include ProgramSupport

  # Everything the installed lookups expect, so a test fails only the step it changes.
  LOOKUPS = "theme: light \e[31;1mmap\e[0m Return transformed values. RichRIExample#map\t\n " \
            "You can use tab to autocomplete. DOCUMENTATION SOURCES"

  def setup
    skip "package:check needs man and groff" unless which("man") && which("groff")
  end

  def test_a_failed_lookup_names_the_command_and_its_output
    _out, err, status = check_package(<<~RUBY)
      warn "rich-ri: cannot read the store"
      exit 1
    RUBY

    command = %r{rich-ri --config /\S+/theme\.yml --show-config}

    assert_equal 1, status.exitstatus
    assert_match(/\Arake: installed lookup failed: #{command}\nrich-ri: cannot read the store\n\z/, err)
  end

  def test_a_failed_command_names_it_and_its_errors
    _out, err, status = check_package(<<~RUBY)
      abort "rich-ri: broken" if ARGV == ["--version"]
      print #{LOOKUPS.dump}
    RUBY

    assert_equal [1, "rake: installed CLI failed: rich-ri --version\nrich-ri: broken\n"], [status.exitstatus, err]
  end

  def test_a_wrong_version_names_what_the_installed_gem_printed
    _out, err, status = check_package(<<~RUBY)
      print ARGV == ["--version"] ? "rich-ri 0.0.0\n" : #{LOOKUPS.dump}
    RUBY

    assert_equal [1, "rake: installed rich-ri --version printed \"rich-ri 0.0.0\"; " \
                     "expected \"rich-ri #{RichRI::VERSION}\"\n"], [status.exitstatus, err]
  end

  def test_a_manual_outside_the_installed_gem_is_named
    _out, err, status = check_package(<<~RUBY)
      case ARGV
      when ["--version"] then puts "rich-ri #{RichRI::VERSION}"
      when ["--man-path"] then puts "/missing/rich-ri.1"
      else print #{LOOKUPS.dump}
      end
    RUBY

    assert_equal [1, "rake: manual missing from installed gem: /missing/rich-ri.1\n"], [status.exitstatus, err]
  end

  private

  # A gem named rich-ri whose executable runs the given Ruby, installed by the real package check.
  def check_package(source)
    runtime = Gem::Specification.load(File.join(TestSupport::ROOT, "rich-ri.gemspec")).runtime_dependencies
    Dir.mktmpdir("rich-ri-package-test-") do |dir|
      FileUtils.mkdir_p(File.join(dir, "exe"))
      File.write(File.join(dir, "exe/rich-ri"), source)
      spec = Gem::Specification.new do |gem|
        gem.name = "rich-ri"
        gem.version = RichRI::VERSION
        gem.summary = "Package check test"
        gem.authors = ["Test"]
        gem.license = "MIT"
        gem.files = ["exe/rich-ri"]
        gem.bindir = "exe"
        gem.executables = ["rich-ri"]
        runtime.each { |dependency| gem.add_dependency(dependency.name, *dependency.requirement.as_list) }
      end
      package = File.join(dir, "rich-ri.gem")
      Dir.chdir(dir) { capture_io { Gem::Package.build(spec, true, false, package) } }
      rake("--quiet", "package:check[#{package}]")
    end
  end
end
