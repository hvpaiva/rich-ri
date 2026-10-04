# frozen_string_literal: true

require "rdoc/ri/driver"
require "prism"
require "reline"
require "io/console"
require "open3"
require "shellwords"
require "timeout"

require_relative "rich_ri/version"
require_relative "rich_ri/ansi"
require_relative "rich_ri/highlighter"
require_relative "rich_ri/formatter"
require_relative "rich_ri/driver"
require_relative "rich_ri/options"
require_relative "rich_ri/completion"
require_relative "rich_ri/cli"
