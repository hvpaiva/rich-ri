# frozen_string_literal: true

require_relative "lib/rich_ri/version"

Gem::Specification.new do |spec|
  spec.name = "rich-ri"
  spec.version = RichRI::VERSION
  spec.authors = ["Highlander Paiva"]
  spec.email = ["contact@hvpaiva.dev"]
  spec.summary = "Readable, colorful Ruby documentation in your terminal"
  spec.description = "A terminal reader for Ruby's RI documentation with semantic colors, Ruby syntax " \
                     "highlighting, shell transcript recognition and dynamic shell completion. " \
                     "Uses the documentation installed for your active Ruby and gems."
  spec.homepage = "https://github.com/hvpaiva/rich-ri"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"
  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "documentation_uri" => "#{spec.homepage}#readme",
    "rubygems_mfa_required" => "true",
    "allowed_push_host" => "https://rubygems.org"
  }
  # An allowlist also builds from a source archive without shipping local files.
  spec.files = Dir.chdir(__dir__) do
    Dir.glob("lib/**/*.rb") + Dir.glob("docs/**/*.{md,yml}") +
      %w[exe/rich-ri completions/rich-ri.bash completions/rich-ri.zsh completions/rich-ri.fish
         man/man1/rich-ri.1 README.md CHANGELOG.md LICENSE.txt SECURITY.md]
  end
  spec.bindir = "exe"
  spec.executables = ["rich-ri"]
  spec.require_paths = ["lib"]
  spec.add_dependency "io-console", "~> 0.8"
  spec.add_dependency "open3", "~> 0.2"
  spec.add_dependency "prism", "~> 1.0"
  spec.add_dependency "psych", "~> 5.2"
  spec.add_dependency "rdoc", "~> 8.1"
  spec.add_dependency "readline", "~> 0.0.4"
  spec.add_dependency "reline", "~> 0.6"
  spec.add_dependency "shellwords", "~> 0.2"
  spec.add_dependency "timeout", "~> 0.4"
end
