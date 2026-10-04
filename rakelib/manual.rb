# frozen_string_literal: true

require_relative "../lib/rich_ri"

module Manual
  def self.render
    escape_code_blocks(<<~ROFF)
      .TH RICH-RI 1 "" "rich-ri #{RichRI::VERSION}" "User Commands"
      .SH NAME
      rich-ri - readable, colorful Ruby documentation
      .SH SYNOPSIS
      .B rich-ri
      [options] [name ...]
      .SH DESCRIPTION
      Read the RI documentation installed for the active Ruby and its gems.
      rich-ri wraps RDoc's RI library, adding a terminal formatter and discovery.
      It does not invoke the ri executable, which need not be on PATH.
      Headings, references, signatures and Ruby examples use the terminal palette.
      With no name, start interactive lookup with Tab completion.
      Submit an empty line to leave interactive lookup.
      Use Class#method for instance methods, Class::method for class methods,
      and Class.method to search both. Quote shell punctuation such as 'Array.[]'.
      .PP
      In less, use / to search, n for the next match, Space for the next page,
      and q to return. Use --no-pager to write directly to stdout.
      Ruby highlighting works without external programs.
      The optional bat program highlights shell transcripts and tagged languages;
      without it, their original text is preserved. less is an optional pager.
      man(1) is needed only for --man; --man-path and --install-man work without it.
      .SH OPTIONS
      #{options}
      .SH EXAMPLES
      .nf
      rich-ri Array#map
      rich-ri 'Array.[]'
      rich-ri ruby:syntax/pattern_matching
      rich-ri --color=always Hash | less -R
      rich-ri --no-standard-docs --doc-dir ./doc/ri MyClass
      .fi
      #{environment}
      #{completion}
      .SH MANUAL INSTALLATION
      RubyGems keeps this page inside the installed gem.
      rich-ri --man opens it directly; rich-ri --man-path prints its location.
      .PP
      Run rich-ri --install-man to copy or update the page in
      $XDG_DATA_HOME/man/man1, or ~/.local/share/man/man1 if XDG_DATA_HOME
      is unset, empty or relative. Use --install-man=DIR for another man1 directory.
      The command prints a MANPATH setting for Bash, Zsh and Fish.
      Its trailing empty entry preserves the system manual search paths.
      Add the setting to your shell configuration if man rich-ri cannot find the page.
      .PP
      Re-run the installation command after upgrading the gem.
      To uninstall the copied page, remove rich-ri.1 from that directory.
      Nothing is installed or removed automatically by gem install or gem uninstall.
      .SH DOCUMENTATION SOURCES
      Use --list-doc-dirs to inspect the searched locations and --list for known classes.
      If a gem lacks documentation, run gem rdoc GEM_NAME --ri.
      Ruby core documentation comes from your Ruby manager or operating system.
      rich-ri does not download or generate documentation while browsing.
      .SH SECURITY
      RI stores are Ruby Marshal data. Read only documentation you trust,
      including when using completion or --dump.
      Examples are never executed. Pager commands and bat come from your environment.
      .SH EXIT STATUS
      0: success (including a closed output pipe); 1: lookup or usage failure;
      130: interrupted.
      .SH SEE ALSO
      ri(1), ruby(1), less(1), bat(1)
      .PP
      Project documentation and support: https://github.com/hvpaiva/rich-ri
    ROFF
  end

  def self.options
    RichRI::Options.new.parser.top.list.filter_map do |entry|
      if entry.respond_to?(:long)
        names = (entry.short + entry.long).join(", ") + entry.arg.to_s
        ".TP\n.B #{escape(names)}\n#{escape(entry.desc.join(' '))}"
      elsif entry.end_with?(":")
        ".SS #{escape(entry.delete_suffix(':'))}"
      end
    end.join("\n")
  end

  def self.environment
    <<~ROFF.chomp
      .SH ENVIRONMENT
      .TP
      .B RI
      Default options, parsed as shell words. Command-line options take precedence.
      Completion uses its documentation-source options but never its actions.
      .TP
      .B RI_PAGER, PAGER
      Choose the documentation pager; RI_PAGER takes precedence.
      These are trusted shell commands.
      .TP
      .B LESS
      Options for less. rich-ri adds -R for its documentation pager only.
      .TP
      .B NO_COLOR, TERM
      A nonempty NO_COLOR or TERM=dumb disables automatic colors.
      --color=always overrides them; --no-color disables rich-ri's colors.
      .TP
      .B MANPAGER, PAGER
      Select the manual viewer's pager, as supported by man(1).
      .TP
      .B MANROFFOPT, GROFF_NO_SGR, LESS_TERMCAP_*
      Existing man formatting and pager settings are respected.
      When colors are enabled and no pager settings exist, rich-ri supplies
      a default less palette for the manual without changing the parent environment.
      .TP
      .B MANPATH, XDG_DATA_HOME
      Manual search paths and the user data directory used by --install-man.
      .TP
      .B BAT_THEME
      Optional bat theme for tagged non-Ruby examples. Shell commands use ansi.
      .TP
      .B GEM_HOME, GEM_PATH, HOME, PATH
      RubyGems documentation locations, home RI store and external program lookup.
    ROFF
  end

  def self.completion
    <<~ROFF.chomp
      .SH COMPLETION
      Completion suggests installed classes, methods, pages, options and values.
      It follows documentation-source options from RI and the command line,
      makes no network requests and leaves broken stores without suggestions.
      .SS Bash
      Load bash-completion 2.x, then run these commands:
      .nf
      data=${XDG_DATA_HOME:-"$HOME/.local/share"}
      dir="$data/bash-completion/completions"
      mkdir -p "$dir"
      rich-ri --completion=bash > "$dir/rich-ri"
      .fi
      .PP
      For the current shell, run source <(rich-ri --completion=bash).
      .SS Zsh
      Add these lines to .zshrc, after any existing completion setup:
      .nf
      autoload -Uz compinit && compinit
      source <(rich-ri --completion=zsh)
      .fi
      .SS Fish
      Run these commands in Fish:
      .nf
      set -l dir "$__fish_config_dir/completions"
      mkdir -p "$dir"
      rich-ri --completion=fish > "$dir/rich-ri.fish"
      .fi
      .SS Optional alias
      To use ri as the short name in Bash, add these lines after loading
      bash-completion:
      .nf
      alias ri='rich-ri'
      source <(rich-ri --completion=bash)
      complete -o filenames -F _rich_ri ri
      .fi
      .PP
      In Zsh, add alias ri='rich-ri' after the completion setup.
      In Fish, add alias ri rich-ri to your configuration.
      command ri still invokes the original RI executable.
      .PP
      Reinstall copied Bash and Fish scripts after upgrading rich-ri.
      Zsh's source command reads the current installed script on shell startup.
    ROFF
  end

  def self.escape(line)
    line.gsub("\\", "\\e").gsub("-", "\\-").sub(/\A(?=[.'])/) { "\\&" }
  end

  # Roff may typeset bare hyphens and apostrophes as Unicode punctuation.
  # Literal commands need the ASCII glyphs so copied examples still run.
  def self.escape_code_blocks(document)
    document.gsub(/^\.nf\n(.*?)^\.fi$/m) do
      code = Regexp.last_match(1).lines.map { |line| escape(line).gsub("'") { "\\(aq" } }.join
      ".nf\n#{code}.fi"
    end
  end
end
