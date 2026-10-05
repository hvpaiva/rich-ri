# frozen_string_literal: true

require "open3"

# Disposable Git repositories for the maintenance tests.
module GitSupport
  # Git exports these to hooks. Left in place, they point fixture commands and
  # the code under test at the repository that started the suite.
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
end
