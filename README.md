# rich-ri

Read Ruby documentation with clear headings, colored references and highlighted
examples, using the RI documentation already installed for your Ruby and gems.

rich-ri wraps Ruby's original RI reader, provided by RDoc. RDoc handles lookup
and documentation stores; rich-ri adds semantic colors, syntax highlighting and
shell completion for classes, methods, documentation pages and options.
It requires the RDoc library, which RubyGems installs as a dependency. Many Ruby
installations already include RDoc and `ri`. rich-ri uses that library directly,
so the separate `ri` executable does not need to be on your `PATH`.

![The same Ruby methods documentation in ri on the left and rich-ri on the right, with colored headings, references, inline code and Ruby examples.](docs/images/ri-vs-rich-ri.png)

Actual output from `ri` (left) and `rich-ri` (right), using the same documentation,
60-column width and terminal palette. The image shows an excerpt of `ruby:syntax/methods`.

```sh
rich-ri Array#map
rich-ri Hash
rich-ri ruby:syntax/pattern_matching
```

Ruby examples are highlighted with Prism. When bat is installed, rich-ri also
highlights explicitly tagged languages and recognizes shell transcripts such as
`$ echo "hello" | ruby example.rb`. Command output stays plain. Colors follow
your terminal's palette by default. You can choose a light or dark preset and
customize each semantic style in a [configuration file](docs/configuration.md).

## Install

Requires Ruby 3.4 or later. The CI matrix covers Ruby 3.4 and 4.0 on Linux, and
Ruby 4.0 on macOS. RDoc 8.1 is the minimum supported RDoc version.

```sh
gem install rich-ri
```

Run `rich-ri` from any shell. Installation does not change your shell configuration.
See [Contributing](CONTRIBUTING.md#set-up) to run a source checkout.

Reading documentation, Ruby highlighting and interactive discovery work without
bat, less or man. These programs add specific capabilities:

- **bat** adds syntax highlighting for shell commands and tagged examples in
  other languages. Without it, those examples remain readable plain code.
- **less**, or another RI-compatible pager, provides scrolling and search.
  `--no-pager` always writes directly to the terminal.
- **man** is needed for `rich-ri --man` and `man rich-ri`. The built-in `--help`
  and manual installation command work without it.

Shell completion has separate setup instructions for Bash, Zsh and Fish below.
Only the Bash adapter requires **bash-completion 2.x**; Zsh and Fish use their
built-in completion systems.

## Read and discover

Names follow RI conventions. Use `Class#method` for instance methods,
`Class::method` for class methods, and `Class.method` to search both.
Quote names containing shell punctuation, such as `rich-ri 'Array.[]'`.

Run `rich-ri` without arguments for RI's interactive lookup. Its Tab completion
is extended with documentation pages and method prefixes such as `String#`,
`String.` and `String::`; submit an empty line to leave. With shell completion
installed, you can also find classes, methods, pages and options before running a command:

```text
rich-ri Str<Tab>
rich-ri String#<Tab>
rich-ri String.<Tab>
rich-ri ruby:<Tab>
rich-ri --<Tab>
```

In less, use `/` to search, `n` for the next match, Space for the next page and
`q` to return. `--no-pager` writes directly to stdout.

Headings keep their RDoc level markers (`=`, `==`, through `======`), in the
same style as the heading text. Horizontal separators use plain hyphens in a
muted style. Search for `^=== ` to find level-three headings or `^---` to find
separators, then use `n` and `N` to move between matches. These markers remain
available with colors disabled.

```sh
rich-ri --all Array
rich-ri --width=72 String#scan
rich-ri --color=always Array#map | less -R
rich-ri --no-color Hash
rich-ri --format=markdown Array#map
```

`--format` selects an original RDoc formatter. Otherwise, disabling colors
preserves rich-ri's page layout. Code blocks keep their content and indentation;
prose wraps by visible terminal width, including wide Unicode characters.

## Shell completion

Completion reads the active Ruby's RI stores, including sources selected in your
configuration file, `RI` or `--doc-dir`. It makes no network requests. It suggests
installed classes, methods, pages, options, theme names and style roles, with
descriptions where available. Invalid configuration or unavailable stores prevent
documentation-name suggestions; options and theme values remain available. Run
`rich-ri --show-config` to diagnose configuration errors.

### Bash

Load bash-completion 2.x in your shell, then install the lazy-loaded script:

```sh
mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions"
rich-ri --completion=bash > "${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/rich-ri"
```

To load it in the current shell, run `source <(rich-ri --completion=bash)`.

### Zsh

After `autoload -Uz compinit && compinit` in your `.zshrc`, add:

```zsh
source <(rich-ri --completion=zsh)
```

### Fish

```fish
mkdir -p "$__fish_config_dir/completions"
rich-ri --completion=fish > "$__fish_config_dir/completions/rich-ri.fish"
```

### Use the short name ri

For Bash, add these lines after loading bash-completion:

```bash
alias ri='rich-ri'
source <(rich-ri --completion=bash)
complete -o filenames -F _rich_ri ri
```

For Zsh, add `alias ri='rich-ri'` after the completion setup. Zsh expands aliases
for completion by default. In Fish, use `alias ri rich-ri` in your configuration;
Fish aliases inherit completions from the wrapped command.

`command ri` still invokes the original RI executable. The alias is optional.

## Documentation sources and missing pages

rich-ri reads installed documentation; it does not download documentation or
generate it while you browse. `rich-ri --list-doc-dirs` shows the searched paths,
and `rich-ri --list` lists known classes.

If a gem was installed with `--no-document`, generate its RI documentation with
`gem rdoc GEM_NAME --ri`. Ruby core documentation depends on how your Ruby was
installed; install the documentation package supplied by your Ruby manager or OS.

### Read your project's documentation

Save this small example as `greeter.rb`:

```ruby
class Greeter
  # Returns a greeting for the given name.
  #
  #   Greeter.new.greet("Ruby") # => "Hello, Ruby!"
  def greet(name)
    "Hello, #{name}!"
  end
end
```

Generate its documentation and read the method:

```sh
rdoc --ri --quiet --op doc/ri greeter.rb
rich-ri --no-standard-docs --doc-dir doc/ri --no-color --no-pager --width=60 Greeter#greet
```

The output below abbreviates the current directory as `.`:

```text
= Greeter#greet

(from ./doc/ri)
------------------------------------------------------------
  greet(name)

------------------------------------------------------------

Returns a greeting for the given name.

  Greeter.new.greet("Ruby") # => "Hello, Ruby!"
```

To use the same documentation sources for lookup and shell completion, configure
`RI` in the current shell:

| Shell | Command |
| --- | --- |
| Bash or Zsh | `export RI='--no-standard-docs --doc-dir doc/ri'` |
| Fish | `set -gx RI '--no-standard-docs --doc-dir doc/ri'` |

Only open RI stores you trust. RI caches use Ruby Marshal serialization; see
[SECURITY.md](SECURITY.md) for the trust boundary.

## Configuration

rich-ri accepts RI's default options from the `RI` environment variable and uses
RDoc's installed documentation stores. It also has its own optional YAML file:
`$XDG_CONFIG_HOME/rich-ri/config.yml`, or `~/.config/rich-ri/config.yml` when
`XDG_CONFIG_HOME` is unset, empty or relative. No project file is loaded automatically.

```yaml
# ~/.config/rich-ri/config.yml
theme: terminal          # terminal, dark or light
color: auto              # auto, always or never
color_depth: auto        # auto, basic, "256" or truecolor
pager: true
styles:
  heading: "blue:bold"
  method: "cyan"
  comment: "bright_black"
```

Settings take precedence in this order, from highest to lowest: command-line
options, dedicated environment variables, the selected YAML file, `RI` default
options, then built-in defaults. Individual style roles merge across these layers.
`doc_dirs` adds directories instead of replacing previous entries; relative paths
in the YAML file are resolved from that file's directory.

```sh
rich-ri --config-path
rich-ri --show-config
rich-ri --theme=light --style='comment=#6b7280' Regexp
rich-ri --config "$HOME/my-rich-ri.yml" Array#map
rich-ri --no-config --show-config
```

`--config` or `RICH_RI_CONFIG` selects another file; an explicitly selected file
must exist. `--no-config` skips the file but keeps environment and command-line
settings. If both selectors appear on the command line, the last one wins.
`--help`, `--version`, `--config-path` and `--completion=SHELL` remain available
when a configuration file is broken.

The `terminal` theme follows your terminal's ANSI palette. `dark` and `light`
provide foreground colors for those backgrounds; they do not change or detect
your terminal background. Override any of the 19 style roles with named ANSI
colors, palette indices, RGB hex colors, foreground/background colors and text
attributes. `none` removes a role's styling. See the
[complete configuration reference](docs/configuration.md) and
[annotated example](docs/config.example.yml) for every key, role and environment
variable, including `RICH_RI_STYLE_<ROLE>` overrides.

| Setting | Behavior |
| --- | --- |
| `RICH_RI_THEME`, `RICH_RI_COLOR`, `RICH_RI_COLOR_DEPTH` | Select the theme, color policy and terminal color depth. |
| `RICH_RI_WIDTH` | Prose width; accepts 20 columns or more. |
| `RICH_RI_CONFIG`, `XDG_CONFIG_HOME` | Select the configuration file or its default parent directory. |
| `RICH_RI_STYLE_<ROLE>` | Override one style, for example `RICH_RI_STYLE_COMMENT=bright_black`. |
| `RICH_RI_BAT_THEME`, `BAT_THEME` | bat theme for tagged non-Ruby, non-shell examples, in that order; default `base16`. |
| `RICH_RI_SHELL_THEME` | bat theme for shell examples and transcript commands; default `ansi`. |
| `RI` | Default options, parsed as shell words; no shell evaluation occurs. |
| `RI_PAGER`, `PAGER` | Trusted pager commands. `RI_PAGER` overrides file settings; `PAGER` is a fallback. |
| `LESS` | Pager preferences; rich-ri adds `-R` for its child documentation pager. |
| `NO_COLOR`, `TERM` | Nonempty `NO_COLOR` or `TERM=dumb` disables automatic colors. |
| `COLORTERM`, `TERM` | Detect truecolor or 256-color capability for `color_depth: auto`. |
| `GEM_HOME`, `GEM_PATH`, `HOME`, `PATH` | Locate RubyGems/home documentation, home configuration and external programs. |
| `MANPAGER`, `MANROFFOPT`, `GROFF_NO_SGR`, `LESS_TERMCAP_*` | Existing manual pager and palette settings take precedence over rich-ri's manual palette. |
| `MANPATH`, `XDG_DATA_HOME` | Locate manuals and select the default manual installation directory. |

Colors default to `auto`: enabled only on a terminal. `--color` or
`--color=always` forces them, including in pipes and when `NO_COLOR` or `TERM=dumb`
is set. `--no-color` disables them while preserving the rich page layout.
`--format` selects an original RDoc formatter, whose output does not use these
semantic styles. The default prose width follows the terminal up to 96 columns.

Ruby syntax highlighting and every page style work without bat. bat uses its own
separately selected themes for other languages; `bat --list-themes` lists those
installed on your machine. Shell detection is conservative: ambiguous prompts,
unclosed quotes and shell heredocs remain plain. Explicit language tags take
precedence. A missing or failing bat leaves the original code readable.

## Manual, development and support

`rich-ri --help` lists every option. `rich-ri --man` opens the bundled manual.
To install a copy for `man rich-ri`, run:

```sh
rich-ri --install-man
```

The command prints the destination and any `MANPATH` configuration needed for
discovery. Use `--install-man=DIR` to choose another `man1` directory. Repeat the
command after upgrading the gem. Bash and Fish completion files are also copies;
rerun their installation commands after an upgrade. Zsh's setup loads the script
from the active gem whenever a new shell starts.

The manual uses color when supported and honors existing pager and palette
settings. `--no-color` disables rich-ri's manual palette.

Exit status is 0 on success, 1 for lookup/usage failures and 130 when interrupted.
A closed output pipe is a normal exit.

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and checks,
[ARCHITECTURE.md](ARCHITECTURE.md) for the rendering and completion boundaries,
and [CHANGELOG.md](CHANGELOG.md) for user-visible changes.
Report bugs or ask usage questions in [GitHub issues](https://github.com/hvpaiva/rich-ri/issues).
Security reports go through the private channel in [SECURITY.md](SECURITY.md).

Released under the [MIT license](LICENSE.txt).
