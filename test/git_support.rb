# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

module GitSupport
  # Git exports these to hooks; left set, they point the tests at the repository running the suite.
  REPOSITORY_VARIABLES = Open3.capture2("git", "rev-parse", "--local-env-vars").first.split.freeze
  REPOSITORY_VARIABLES.each { |name| ENV.delete(name) }
  ENVIRONMENT = { "GIT_CONFIG_GLOBAL" => File::NULL, "GIT_CONFIG_NOSYSTEM" => "1" }.freeze
  # Detached maintenance can race with the removal of a temporary repository.
  SETTINGS = %w[user.name=Test user.email=test@example.org commit.gpgsign=false core.hooksPath=/dev/null
                init.defaultBranch=main maintenance.auto=false].flat_map { |setting| ["-c", setting] }.freeze

  def git(root, *)
    out, err, status = Open3.capture3(ENVIRONMENT, "git", *SETTINGS, *, chdir: root)

    assert_predicate status, :success?, err
    out.strip
  end

  # Commands that check origin first find it in this repository through GIT_DIR.
  def github_origin(url = "https://github.com/hvpaiva/rich-ri.git")
    Dir.mktmpdir("rich-ri-origin-") do |root|
      git(root, "init", "-q")
      git(root, "remote", "add", "origin", url)
      yield ENVIRONMENT.merge("GIT_DIR" => File.join(root, ".git"))
    end
  end

  def commit(root, files)
    files.each do |path, content|
      FileUtils.mkdir_p(File.dirname(File.join(root, path)))
      File.write(File.join(root, path), content)
    end
    git(root, "add", "-A")
    git(root, "commit", "-qm", "test: change fixture")
    git(root, "rev-parse", "HEAD")
  end
end
