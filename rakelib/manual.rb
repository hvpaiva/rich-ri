# frozen_string_literal: true

require_relative "../lib/rich_ri"

# The options come from the same descriptions as --help.
module Manual
  class Error < StandardError; end

  CHANGELOG = File.expand_path("../CHANGELOG.md", __dir__)
  RELEASE = /^## \[#{Regexp.escape(RichRI::VERSION)}\] - (\d{4}-\d{2}-\d{2})$/
  REQUESTS = %w[.SH .SS .TP .PP .B .I .nf .fi].freeze
  # roff typesets these as a breakable hyphen, a curly quote or an accent; the escapes keep
  # the ASCII character, so a name or command copied from the page works.
  ESCAPES = { "\\" => "\\e", "-" => "\\-", "'" => "\\(aq", "`" => "\\(ga", "^" => "\\(ha",
              "~" => "\\(ti" }.freeze

  def self.render
    header + roff(<<~SOURCE)
      .SH NAME
      rich-ri - readable, colorful Ruby documentation
      .SH SYNOPSIS
      .B rich-ri
      [options] [name ...]
      .SH DESCRIPTION
      Read the RI documentation installed for the active Ruby and its gems.
      rich-ri wraps RDoc's RI library, adding colors, syntax highlighting,
      documentation-page completion and shell completion for names and options.
      It does not invoke the ri executable, which need not be on PATH.
      Headings, references, signatures and Ruby examples use the selected theme.
      The default theme follows the terminal palette.
      With no name, or with --interactive, look names up at a prompt with
      Tab completion. Each answer opens in the pager, as a single lookup does.
      Submit an empty line to leave the prompt.
      Use Class#method for instance methods, Class::method for class methods,
      and Class.method to search both. Quote shell punctuation such as 'Array.[]'.
      Use SOURCE:PAGE for a documentation page, where SOURCE is ruby, site, home,
      a gem's name or the full name of its directory, such as rake or
      rake-13.2.1, or a directory given with --doc-dir. A gem is named in
      full: a prefix such as http does not find http-2.
      .PP
      In less, use / to search, n for the next match, Space for the next page,
      and q to return. Use --no-pager to write directly to stdout.
      Headings retain their level markers (= through ======) in the heading style.
      Horizontal separators use hyphens in a muted style.
      Search for ^=== followed by a space to find level-three headings,
      or ^--- to find separators. These markers also appear without colors.
      .PP
      Ruby highlighting works without external programs.
      The optional bat program highlights shell transcripts and tagged languages;
      without it, their original text is preserved. less is an optional pager.
      man(1) is needed only for --man; --man-path and --install-man work without it.
      .PP
      --server requires the optional webrick gem (gem install webrick).
      It serves RDoc's web interface on port #{RichRI::Options::DEFAULT_PORT} by default, listening on all
      interfaces; --server=PORT chooses another port from #{RichRI::Options::PORTS.min} to #{RichRI::Options::PORTS.max}.
      Stop it with Ctrl-C.
      Terminal themes do not apply to web pages.
      --profile requires the optional profile gem (gem install profile) and
      prints profiling information when the command exits.
      Install these gems for the active Ruby; with bundle exec, include them in
      that bundle. Missing optional gems produce an installation hint and status 1.
      .SH OPTIONS
      Write long options and their listed values in full; abbreviations are not accepted.
      Options may follow names; -- ends them.
      .PP
      A command does one thing. --help answers before anything else and
      --version before the rest, so either can be added to any command line
      whose options and values are valid.
      No two of #{listing(exclusive_actions)} can be combined.
      --interactive takes no names; --no-interactive requires one.
      An action given on the command line replaces one set in RI.
      #{options}
      .SH EXAMPLES
      .nf
      rich-ri Array#map
      rich-ri 'Array.[]'
      rich-ri ruby:syntax/pattern_matching
      rich-ri --color=always Hash | less -R
      rich-ri --no-standard-docs --doc-dir ./doc/ri MyClass
      .fi
      #{configuration}
      #{styles}
      #{environment}
      #{files}
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
      RI caches can be incompatible across Ruby major versions.
      Regenerate incompatible documentation with the current Ruby and RDoc.
      rich-ri does not download or generate documentation while browsing.
      .SH SECURITY
      RI stores are Ruby Marshal data. Read only documentation you trust,
      including when using completion or --dump.
      Examples are never executed. Configuration uses safe YAML parsing, with no
      object tags, aliases or code evaluation. No project configuration is loaded
      automatically. Pager commands and selected RI stores must still be trusted.
      bat comes from PATH; its configuration file is disabled.
      bat calls have a two-second deadline, a 1 MiB input limit and an 8 MiB output limit.
      Failed or invalid output leaves the original text and disables bat for the rest of the page.
      .SH EXIT STATUS
      .TP
      .B 0
      Success, including output cut short by a closed pipe.
      .TP
      .B 1
      Failure: a name that was not found, also when similar names or the pages
      of its source are shown in its place; documentation that cannot be read;
      a refused configuration file or environment variable; a pager, manual
      viewer or optional gem that cannot run.
      .TP
      .B 2
      Usage error: an unknown option, a refused value, or options and names
      that cannot be combined.
      .TP
      .B 130
      Interrupted with Ctrl-C.
      .SH SEE ALSO
      ri(1), ruby(1), less(1), bat(1)
      .PP
      Project documentation and support: https://github.com/hvpaiva/rich-ri
    SOURCE
  end

  # The release date keeps the page reproducible; it is left unescaped because formatters read it.
  def self.header
    <<~ROFF
      .\\" Generated by "bundle exec rake generate" from rakelib/manual.rb and the
      .\\" option descriptions in lib/rich_ri. Do not edit this file.
      .TH RICH\\-RI 1 "#{release_date}" "rich\\-ri #{RichRI::VERSION}" "User Commands"
      .\\" The page is full of names to copy: no word is hyphenated or stretched.
      .nh
      .ad l
      .nr HY 0
      .ds AD l
    ROFF
  end

  def self.exclusive_actions
    RichRI::Actions::OPTIONS.reject { |_option, name| RichRI::Actions::FIRST.include?(name) }.keys
  end

  def self.listing(words)
    "#{words[0...-1].join(', ')} and #{words.last}"
  end

  def self.release_date
    File.read(CHANGELOG)[RELEASE, 1] or
      raise Error, "#{CHANGELOG} has no \"## [#{RichRI::VERSION}] - YYYY-MM-DD\" heading"
  end

  def self.options
    sections.flat_map do |title, switches|
      [".SS #{title}"] + switches.flat_map do |switch|
        [".TP", ".B #{(switch.short + switch.long).join(', ')}#{switch.arg}", switch.desc.join(" ")]
      end
    end.join("\n")
  end

  # The notes after the last option have headings too, with no options under them.
  def self.sections
    entries = RichRI::Options.new.parser.top.list
    entries.slice_before { |entry| entry.is_a?(String) && entry.end_with?(":") }.filter_map do |title, *group|
      switches = group.select { |entry| entry.respond_to?(:long) }
      [title.delete_suffix(":"), switches] unless switches.empty?
    end
  end

  def self.configuration
    <<~SOURCE.chomp
      .SH CONFIGURATION
      The optional user file is $XDG_CONFIG_HOME/rich-ri/config.yml when
      XDG_CONFIG_HOME is absolute and nonempty; otherwise use
      ~/.config/rich-ri/config.yml. No project file is loaded automatically.
      The file is specific to rich-ri; the original ri does not read it.
      .PP
      RICH_RI_CONFIG or --config FILE selects another file, which must exist.
      --no-config disables file loading. The last command-line file selector wins.
      Neither option is accepted in RI, which is read after the file is chosen.
      --config-path prints the selected path without reading it.
      --show-config prints the effective settings as YAML without editing a file.
      Review its paths and command arguments before sharing the output.
      .PP
      Precedence, from lowest to highest: built-in defaults, RI default options,
      the selected YAML file, dedicated environment variables, command-line flags.
      Styles merge by role; each override replaces that role's complete style.
      Documentation directories accumulate from RI, the file and the command line.
      Relative doc_dirs in YAML resolve from the file's own directory.
      .PP
      Use a single YAML mapping; an empty file means no overrides. Files over
      64 KiB, nesting over 20 levels, duplicate or unknown keys, wrong types,
      invalid values, aliases and object tags are errors. No Ruby or shell evaluation occurs.
      --help, --version, --config-path and --completion=SHELL still work with a
      broken file. Use --no-config to bypass it for other commands.
      .SS File keys
      .TP
      .B theme
      terminal (default), dark or light. Presets change foreground colors;
      they do not detect or set the terminal background.
      .TP
      .B color
      auto (default), always or never. Auto colors only terminal output, unless
      NO_COLOR is nonempty or TERM is dumb. --color means always.
      --color=always overrides NO_COLOR and TERM=dumb, including in pipes.
      .TP
      .B color_depth
      auto (default), basic, "256" or truecolor. Auto uses COLORTERM=truecolor
      or 24bit first, then TERM containing 256color, then basic ANSI colors.
      Colors are approximated when the selected depth cannot represent them.
      This setting applies to built-in styles; bat handles its own color depth.
      .TP
      .B width
      Integer from 20 to 10000 terminal columns. The default follows terminal width
      minus two, bounded between 30 and 96. Redirected output normally uses 78.
      Code blocks preserve their original content and indentation.
      .TP
      .B pager
      true (default), false, or a trusted command such as "less -R". The command
      is split into words and run directly, without a shell.
      RI_PAGER overrides a file command; --pager-command overrides both, and on
      the command line it pages even when the file says false.
      PAGER is used when none of them names a pager.
      A pager named in any of these ways has to start and to end without failure,
      or the lookup fails with status 1. When none is named, #{listing(RichRI::Pager::USUAL)}
      are tried, and the page is written to the terminal if none exists.
      --no-pager disables paging; redirected output is not paged.
      .TP
      .B bat_theme, shell_theme
      bat themes for non-Ruby, non-shell examples (default base16) and shell examples or
      transcript commands (default ansi). Run bat --list-themes for installed themes.
      Role overrides do not recolor bat output. Missing or failing bat leaves plain code.
      .TP
      .B all, expand_refs
      Booleans: all defaults to false; expand_refs defaults to true. Include all
      methods on class pages, or ask RDoc to expand references at the end of a page.
      .TP
      .B doc_dirs
      List of additional existing, trusted RI directories. Default: empty list.
      .TP
      .B sources
      Mapping of system, site, home and gems to booleans. All default to true.
      These select standard RI stores; --no-standard-docs disables all four.
      .TP
      .B styles
      Mapping of semantic role names to style strings. See STYLES below.
      .SS Example
      .nf
      theme: dark
      width: 72
      styles:
        method: "green:bold"
        comment: "italic"
      .fi
      .PP
      Original RDoc formatters selected with --format do not use rich-ri themes,
      semantic styles or page layout. Ruby highlighting needs no external program.
      The repository includes docs/configuration.md and an annotated
      docs/config.example.yml with every key and role.
    SOURCE
  end

  def self.styles
    <<~SOURCE.chomp
      .SH STYLES
      Set styles in YAML, with RICH_RI_STYLE_<ROLE> environment variables,
      or repeatable --style=ROLE=STYLE flags. Example:
      .nf
      rich-ri --style='comment=#9ca3af' Regexp
      .fi
      .PP
      Separate components with colons. A bare color sets the foreground.
      Use fg=COLOR and bg=COLOR for explicit foreground and background.
      Colors are black, red, green, yellow, blue, magenta, cyan, white,
      their bright_ variants, an index from 0 through 255, or #RRGGBB.
      Use default, fg=default or bg=default to restore the terminal's
      default foreground or background color.
      Attributes are bold, italic, underline, dim, strike and reverse.
      Names are lowercase. Use none by itself to disable a role.
      Raw ANSI escapes and unknown values are rejected.
      Quote numeric and hex styles in YAML so they remain strings.
      .nf
      heading: "fg=#7aa2f7:bold"
      method: "cyan"
      link: "blue:underline"
      muted: "none"
      .fi
      .SS Semantic roles
      title: page title and help usage heading; heading: main sections;
      subheading: nested sections; code: inline code, Ruby variables and literals,
      interpolation and shell prompts; reference: names and method lists;
      link: labeled documentation and external links; label: labeled content;
      muted: secondary metadata and separators; emphasis: emphasized prose;
      bold: strong prose; strike: struck-through prose.
      .PP
      Ruby roles: keyword, string (including regular expressions), number,
      constant, symbol, method (definitions, calls and signatures), comment and operator.
      All 19 roles accept the same style grammar. Theme presets can be
      overridden one role at a time. Terminal support determines attribute appearance.
    SOURCE
  end

  def self.environment
    <<~SOURCE.chomp
      .SH ENVIRONMENT
      Empty dedicated RICH_RI_* variables are ignored.
      .TP
      .B RICH_RI_CONFIG, XDG_CONFIG_HOME
      Explicit file path and default configuration parent. See CONFIGURATION.
      .TP
      .B RICH_RI_THEME, RICH_RI_COLOR, RICH_RI_COLOR_DEPTH
      Override the corresponding file keys. Explicit flags take precedence.
      .TP
      .B RICH_RI_WIDTH
      Override prose width; an integer from 20 to 10000.
      .TP
      .B RICH_RI_STYLE_<ROLE>
      Override one style, using its uppercase role name, for example
      RICH_RI_STYLE_COMMENT=cyan. Explicit --style flags take precedence.
      .TP
      .B RICH_RI_BAT_THEME, BAT_THEME
      Override bat_theme in that order, below --bat-theme. Default: base16.
      .TP
      .B RICH_RI_SHELL_THEME
      Override shell_theme, below --shell-theme. Default: ansi.
      .TP
      .B RICH_RI_DEBUG
      When nonempty, a failure is followed by the error class and its backtrace.
      .TP
      .B RI
      Default options, parsed as shell words without shell evaluation.
      File settings, dedicated environment variables and explicit flags override them.
      Completion uses documentation-source options but never utility actions.
      .TP
      .B RI_PAGER, PAGER
      Trusted documentation pager commands, run without a shell.
      RI_PAGER overrides a file command; PAGER is used when no other names a
      pager. --pager-command takes precedence over both.
      .TP
      .B LESS
      Your options for less. For its own pager only, rich-ri puts -R ahead of
      them so that colors show. When LESS is unset it uses -R -Fi: leave at once
      if the page fits the screen, and ignore case in searches.
      .TP
      .B NO_COLOR, TERM
      A nonempty NO_COLOR or TERM=dumb disables automatic colors.
      --color=always overrides them; --no-color disables rich-ri's colors.
      .TP
      .B COLORTERM, TERM
      Automatic color depth: truecolor or 24bit in COLORTERM, then 256color
      in TERM, then the basic ANSI palette.
      .TP
      .B MANPAGER, PAGER
      Select the manual viewer's pager, as supported by man(1).
      .TP
      .B MANROFFOPT, GROFF_NO_SGR, LESS_TERMCAP_*
      Existing man formatting and pager settings are respected.
      When colors are enabled and no pager settings exist, rich-ri supplies
      a less palette using the selected heading and link styles.
      Parent environment settings are not changed.
      .TP
      .B MANPATH, XDG_DATA_HOME
      Manual search paths and the user data directory used by --install-man.
      .TP
      .B GEM_HOME, GEM_PATH, HOME, PATH
      RubyGems documentation locations, home RI store and external program lookup.
      HOME also supplies the fallback user configuration location.
      Lookups, --list, --list-doc-dirs, --server and --install-man without a
      directory need HOME to be an absolute path. --help, --version,
      --config-path, --show-config, --completion, --man, --man-path, --dump and
      --install-man=DIR work without it.
    SOURCE
  end

  def self.files
    <<~SOURCE.chomp
      .SH FILES
      .TP
      .I $XDG_CONFIG_HOME/rich-ri/config.yml
      The user's configuration file; ~/.config/rich-ri/config.yml when
      XDG_CONFIG_HOME is unset, empty or relative. See CONFIGURATION.
      .TP
      .I $XDG_DATA_HOME/man/man1/rich-ri.1
      The copy of this page written by --install-man;
      ~/.local/share/man/man1/rich-ri.1 when XDG_DATA_HOME is unset, empty or
      relative. See MANUAL INSTALLATION.
    SOURCE
  end

  def self.completion
    <<~SOURCE.chomp
      .SH COMPLETION
      Completion suggests installed classes, methods, pages, options and values.
      It follows documentation sources from RI, the configuration file and explicit
      arguments. It suggests theme names and semantic style roles as well as RI names.
      It makes no network requests. Invalid configuration or broken stores prevent
      documentation-name suggestions; options and theme values remain available.
      Names are not suggested either where the lookup would refuse the command
      line: an invalid option or value, two actions, --interactive with a name,
      or invalid RI options.
      Use --show-config and --list-doc-dirs to diagnose missing names.
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
    SOURCE
  end

  def self.roff(source)
    source.each_line(chomp: true).map do |line|
      request, argument = line.split(" ", 2)
      next "#{escape(line)}\n" unless REQUESTS.include?(request)

      argument ? "#{request} #{escape(argument)}\n" : "#{request}\n"
    end.join
  end

  # A line starting with a period is read as a request; \& in front makes it text.
  def self.escape(text)
    text.gsub(/[\\\-'`^~]/, ESCAPES).sub(/\A(?=\.)/) { "\\&" }
  end
end
