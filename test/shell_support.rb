# frozen_string_literal: true

require "open3"

# Used by the test runner and shell tests to select the same native toolchain.
module ShellSupport
  COMPLETION_PATHS = %w[/usr/share/bash-completion/bash_completion
                        /opt/homebrew/share/bash-completion/bash_completion
                        /usr/local/share/bash-completion/bash_completion].freeze
  ENVIRONMENT = {
    "BASH_ENV" => nil, "ENV" => nil, "BASH_COMPLETION_USER_FILE" => File::NULL,
    # Some versions ship _init_completion in the package's compat directory.
    "BASH_COMPLETION_USER_DIR" => File::NULL, "BASH_COMPLETION_COMPAT_DIR" => nil
  }.freeze
  PROBE = <<~BASH
    (( BASH_VERSINFO[0] >= 4 )) || exit 1
    source "$1" || exit 1
    declare -F _init_completion >/dev/null || exit 1
    (( ${BASH_COMPLETION_VERSINFO[0]:-0} >= 2 ))
  BASH

  def self.available?
    %w[bash zsh fish].all? { |name| executable?(name) } && !bash_completion.nil?
  end

  # Whether there is a bash the completion script supports. It needs none of
  # bash-completion, but compopt, which came with bash 4.
  def self.bash?
    _out, _err, status = Open3.capture3(ENVIRONMENT, "bash", "--noprofile", "--norc", "-c",
                                        "(( BASH_VERSINFO[0] >= 4 ))")
    status.success?
  rescue Errno::ENOENT
    false
  end

  def self.executable?(name)
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
      path = File.join(directory, name)
      File.file?(path) && File.executable?(path)
    end
  end

  def self.bash_completion(paths: COMPLETION_PATHS)
    paths.find do |path|
      next false unless File.file?(path)

      _out, _err, status = Open3.capture3(ENVIRONMENT, "bash", "--noprofile", "--norc", "-c", PROBE,
                                          "rich-ri-shell-probe", path)
      status.success?
    end
  rescue Errno::ENOENT
    nil
  end
end
