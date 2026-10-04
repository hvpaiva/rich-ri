# frozen_string_literal: true

require_relative "../lib/rich_ri"

module Manual
  def self.render
    options = RichRI::Options.new.parser.to_s.lines
    <<~ROFF
      .TH RICH-RI 1 "" "rich-ri #{RichRI::VERSION}" "User Commands"
      .SH NAME
      rich-ri - readable, colorful Ruby documentation
      .SH SYNOPSIS
      .B rich-ri
      [options] [name ...]
      .SH DESCRIPTION
      Read the RI documentation installed for the active Ruby and its gems.
      Headings, references, signatures and Ruby examples use the terminal palette.
      With no name, start interactive lookup with Tab completion.
      .SH OPTIONS
      .nf
      #{options.map { |line| escape(line.chomp) }.join("\n")}
      .fi
      .SH EXAMPLES
      .nf
      rich-ri Array#map
      rich-ri 'Array.[]'
      rich-ri ruby:syntax/pattern_matching
      rich-ri --color=always Hash | less -R
      rich-ri --no-standard-docs --doc-dir ./doc/ri MyClass
      .fi
      .SH ENVIRONMENT
      .TP
      .B RI
      Default options, parsed as shell words. Command-line options take precedence.
      .TP
      .B RI_PAGER, PAGER
      Choose the pager; RI_PAGER takes precedence. These are trusted shell commands.
      .TP
      .B LESS
      Options for less. rich-ri adds -R for its child pager only.
      .TP
      .B NO_COLOR
      A nonempty value disables automatic colors. --color=always overrides it.
      .TP
      .B TERM
      TERM=dumb disables automatic colors.
      .TP
      .B BAT_THEME
      Optional bat theme for tagged non-Ruby examples. Shell commands use ansi.
      .TP
      .B GEM_HOME, GEM_PATH, HOME, PATH
      RubyGems documentation locations, home RI store and external program lookup.
      .SH COMPLETION
      rich-ri --completion=bash, --completion=zsh or --completion=fish prints
      an installable script. See README.md for installation and aliases.
      .SH SECURITY
      RI stores are Ruby Marshal data. Read only documentation you trust.
      Examples are never executed. Pager commands and bat come from your environment.
      .SH EXIT STATUS
      0: success (including a closed output pipe); 1: lookup or usage failure;
      130: interrupted.
      .SH SEE ALSO
      ri(1), ruby(1), less(1), bat(1)
    ROFF
  end

  def self.escape(line)
    line.gsub("\\", "\\e").gsub("-", "\\-").sub(/\A(?=[.'])/, "\\&")
  end
end
