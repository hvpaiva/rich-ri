# frozen_string_literal: true

require "open3"
require "tmpdir"
require "git_support"

module CommitSupport
  include GitSupport

  def repository
    Dir.mktmpdir("rich-ri-commits-") do |root|
      git(root, "init", "-q")
      git(root, "commit", "--allow-empty", "-qm", "chore: initialize")
      yield root
    end
  end

  def lint(root, *arguments, **env)
    arguments = ["HEAD"] if arguments.empty?
    Open3.capture3({ "PR_TITLE" => nil, "PR_BODY" => nil }.merge(env), RbConfig.ruby,
                   File.join(TestSupport::ROOT, "bin/lint-commits"), *arguments, chdir: root)
  end
end
