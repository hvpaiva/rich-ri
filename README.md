# rich-ri

Read Ruby documentation with clear headings, colored references and highlighted
examples, using the RI documentation already installed for your Ruby and gems.

```sh
rich-ri Array#map
rich-ri Hash
rich-ri ruby:syntax/pattern_matching
```

Ruby examples are highlighted with Prism. When bat is installed, rich-ri also
highlights explicitly tagged languages and recognizes shell transcripts such as
`$ echo "hello" | ruby example.rb`. Command output stays plain. Colors follow
your terminal's palette, including light themes.

## Install

Requires Ruby 3.4 or later. The CI matrix covers Ruby 3.4 and 4.0 on Linux, and
Ruby 4.0 on macOS. RDoc 8.1 is the minimum supported RDoc version.

The first RubyGems release is being prepared. To try a source checkout:

```sh
git clone https://github.com/hvpaiva/rich-ri.git
cd rich-ri
bundle install
bundle exec rake build
gem install --local pkg/rich-ri-0.1.0.gem
```

After publication, install the gem with `gem install rich-ri`. The executable
has the same name. No shell configuration is changed during installation.

Optional programs:

- **less** provides scrolling and search. Any RI-compatible pager works.
- **bat** highlights shell commands and tagged examples in other languages.
  Ruby highlighting works without it.
- **man** opens the bundled manual with `rich-ri --man`.
- **bash-completion 2.x** is required for Bash completion.

## Read and discover

Names follow RI conventions. Use `Class#method` for instance methods,
`Class::method` for class methods, and `Class.method` to search both.
Quote names containing shell punctuation, such as `rich-ri 'Array.[]'`.

Run `rich-ri` without arguments for interactive lookup. Press Tab to discover
classes, methods and documentation pages; type `exit` to leave. With shell
completion installed, the same discovery is available before running a command:

```text
rich-ri Str<Tab>
rich-ri String#<Tab>
rich-ri String.<Tab>
rich-ri ruby:<Tab>
rich-ri --<Tab>
```

In less, use `/` to search, `n` for the next match, Space for the next page and
`q` to return. `--no-pager` writes directly to stdout.

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

Completion reads the active Ruby's RI stores, including `--doc-dir`. It makes no
network requests. It can suggest installed classes, methods, pages, options and
option values. Invalid or unavailable stores produce no suggestions.

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
mkdir -p ~/.config/fish/completions
rich-ri --completion=fish > ~/.config/fish/completions/rich-ri.fish
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

To read a project's generated RI store:

```sh
rdoc --ri --op doc/ri lib
rich-ri --no-standard-docs --doc-dir doc/ri MyClass
```

Only open RI stores you trust. RI caches use Ruby Marshal serialization; see
[SECURITY.md](SECURITY.md) for the trust boundary.

## Configuration

| Setting | Behavior |
| --- | --- |
| `--color=auto` | Default: colors only on a TTY, unless `NO_COLOR` is nonempty or `TERM=dumb`. |
| `--color`, `--color=always` | Force colors, including in pipes. |
| `--no-color`, `--color=never` | Disable colors. |
| `RI` | Default options, parsed as shell words. Explicit arguments take precedence. |
| `RI_PAGER`, `PAGER` | Select the pager, in that order. These are trusted shell commands. |
| `LESS` | Pager preferences; rich-ri adds `-R` for its child pager. |
| `BAT_THEME` | bat theme for tagged languages; shell commands use `ansi`. |
| `GEM_HOME`, `GEM_PATH` | Select the active RubyGems documentation stores. |
| `HOME`, `PATH` | Locate home documentation and external programs. |

The default prose width follows the terminal up to 96 columns. `--width` accepts
20 columns or more. Shell detection is intentionally conservative: ambiguous
prompts, unclosed quotes and shell heredocs remain plain. Explicit language tags
take precedence over detection. A missing or failing bat leaves the code readable.

## Manual, development and support

`rich-ri --help` lists every option. `rich-ri --man` opens the bundled manual.
To make `man rich-ri` work independently, copy the file from `rich-ri --man-path`
to your user man directory (commonly `~/.local/share/man/man1`).

Exit status is 0 on success, 1 for lookup/usage failures and 130 when interrupted.
A closed output pipe is a normal exit.

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and checks,
[ARCHITECTURE.md](ARCHITECTURE.md) for the rendering and completion boundaries,
and [CHANGELOG.md](CHANGELOG.md) for user-visible changes.
Report bugs or ask usage questions in [GitHub issues](https://github.com/hvpaiva/rich-ri/issues).
Security reports go through the private channel in [SECURITY.md](SECURITY.md).

Released under the [MIT license](LICENSE.txt).
