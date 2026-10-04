# Configuration

rich-ri uses the original RDoc RI reader for documentation lookup. Its `RI`
environment variable, installed documentation and pager settings still apply.
The YAML file described here is specific to rich-ri; plain `ri` does not read it.
All settings are optional.

## Select a file

The default path is `$XDG_CONFIG_HOME/rich-ri/config.yml` when `XDG_CONFIG_HOME`
is a nonempty absolute path; otherwise it is `~/.config/rich-ri/config.yml`.
A missing default file is fine. rich-ri never searches the current project for
configuration, and installing the gem does not create or edit configuration.

Use `RICH_RI_CONFIG` or `--config FILE` to choose a different file. The explicit
file must exist and be readable. `--config=FILE` is equivalent. `--no-config`
disables file loading, including `RICH_RI_CONFIG`. If `--config` and `--no-config`
appear together, the last command-line selector wins.

```sh
rich-ri --config-path
rich-ri --config "$HOME/my-rich-ri.yml" --show-config
rich-ri --no-config --show-config
```

`--config-path` prints the selected file path without opening it. `--show-config`
prints the effective preferences as YAML after validation and merging; it does not
write a file or load documentation. It includes environment overrides, so check
its contents before sharing it. It shows the requested color policy and depth;
`auto` still depends on the terminal when rendering. `pager: true` means paging
is allowed; redirected output still bypasses the pager. The `styles` map lists
explicit role overrides; preset styles are selected by `theme`.

Use a single YAML document containing a mapping; an empty file means no
overrides. Files larger than 64 KiB, nesting deeper than 20 levels, duplicate or
unknown keys, wrong types, invalid values, YAML aliases and object tags are
rejected with a usage error. Values are not interpolated or evaluated as Ruby
or shell code. A bad file does not prevent
`--help`, `--version`, `--config-path` or printing a shell completion script.
`--no-config` bypasses the bad file to let you continue using the reader.

## Precedence and RI compatibility

Settings are applied in this order, with later layers taking precedence:

1. Built-in defaults.
2. Default options in `RI`, split into shell words without shell evaluation.
3. The selected YAML configuration file.
4. Dedicated environment variables listed below.
5. Explicit command-line options.

The `RI` variable can contain default lookup and presentation options.
For example, `RI='--no-standard-docs --doc-dir /path/to/ri'` works for both lookup
and completion. rich-ri uses RDoc directly; the `ri` executable itself need not
be on `PATH`. rich-ri's extra theme, style and utility flags are not supported
by plain `ri`.

Most values replace earlier values. `styles` merges by role: a later `method`
style changes that role without dropping a `heading` style from an earlier layer.
A role override replaces the preset's entire style for that role.
Documentation directories are additive: `RI`, `doc_dirs` and repeatable
`--doc-dir` options contribute directories in that order.

`RI_PAGER` overrides a pager command from the file. `--pager-command` takes
precedence over both. `PAGER` is used only when no specific pager command was
selected. `--no-pager` disables paging even when a command is configured.
Output redirected to a pipe or file is not paged.

## File keys

Every key is optional. The [annotated example](config.example.yml) includes all
supported keys and style roles.

| Key | Default | Accepted values and behavior |
| --- | --- | --- |
| `theme` | `terminal` | `terminal`, `dark` or `light`. |
| `color` | `auto` | `auto`, `always` or `never`. |
| `color_depth` | `auto` | `auto`, `basic`, `"256"` or `truecolor`. |
| `width` | Terminal-based | Integer of at least 20; prose width in terminal columns. |
| `pager` | `true` | `true` to allow paging, `false` to disable it, or a trusted command string such as `less -R`. |
| `bat_theme` | `base16` | bat theme for tagged non-Ruby, non-shell examples. |
| `shell_theme` | `ansi` | bat theme for shell examples and commands inside transcripts. |
| `all` | `false` | Boolean; include all methods when reading a class or module. |
| `expand_refs` | `true` | Boolean; ask RDoc to expand references at the end of a page. |
| `doc_dirs` | `[]` | List of extra RI directories; relative entries are resolved from the configuration file's directory. |
| `sources` | All enabled | Mapping of `system`, `site`, `home` and `gems` to booleans. |
| `styles` | Theme preset | Mapping of semantic roles to style strings, described below. |

When width is not specified, the reader uses the terminal width minus two
columns, bounded between 30 and 96 columns. With redirected output it normally
uses 78 columns. Code blocks retain their original content and indentation.

`doc_dirs` must name existing directories. Use `sources` to disable selected
standard documentation locations; use `--no-standard-docs` to disable all four
from the command line. This changes which documentation is read, not which
packages are installed. `--list-doc-dirs` prints the resulting search paths.
RI stores contain Ruby Marshal data and must be trusted, even for completion.

A pager command is a trusted executable setting: RDoc may execute it through a
shell. Keep such commands under your own control. Merely reading or inspecting
configuration does not start a pager.

## Themes and styles

`terminal` uses your terminal's ANSI palette, preserving rich-ri's default
appearance. `dark` and `light` supply foreground colors suited to those
backgrounds. They do not set the terminal background or try to detect it.
Choose explicitly if your terminal palette needs different contrast.

Each style is a colon-separated string. A bare color sets the foreground;
`fg=COLOR` and `bg=COLOR` set foreground and background explicitly. Attributes
can be combined with colors. Use `none` by itself to remove a role's styling.

| Component | Values or example |
| --- | --- |
| ANSI foreground | `black`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white` |
| Bright ANSI foreground | `bright_black`, `bright_red`, `bright_green`, `bright_yellow`, `bright_blue`, `bright_magenta`, `bright_cyan`, `bright_white` |
| Palette index | `"0"` through `"255"`, for example `"208"` |
| RGB foreground | `"#RRGGBB"`, for example `"#7aa2f7"` |
| Terminal default | `default`, `fg=default` or `bg=default`; restore the terminal's default foreground or background. |
| Explicit colors | `"fg=#7aa2f7:bg=#1a1b26"` |
| Attributes | `bold`, `italic`, `underline`, `dim`, `strike`, `reverse` |
| Combined style | `"fg=cyan:bg=black:bold:underline"` |
| Disable role | `"none"` |

Names are lowercase. Each color component or attribute may appear only once.
Quote numeric and hex styles in YAML so that they remain
strings; an unquoted `#` starts a YAML comment. Raw ANSI escape sequences and
unknown attributes are rejected. Attribute appearance depends on your terminal.

| Role | Applies to |
| --- | --- |
| `title` | Page titles and the help usage heading. |
| `heading` | Main section headings. |
| `subheading` | Nested section headings. |
| `code` | Inline code, Ruby variables, boolean literals, `self`, interpolation and shell prompts. |
| `reference` | Recognized names, method lists, list markers and displayed URLs. |
| `link` | Labeled documentation and external links. |
| `label` | List labels and other labeled content. |
| `muted` | Secondary metadata and separators. |
| `emphasis` | Emphasized prose. |
| `bold` | Strong prose. |
| `strike` | Struck-through prose. |
| `keyword` | Ruby keywords. |
| `string` | Ruby strings, regular expressions and string-like literals. |
| `number` | Ruby numeric literals. |
| `constant` | Ruby constants. |
| `symbol` | Ruby symbols. |
| `method` | Ruby method definitions, calls and signatures. |
| `comment` | Ruby comments. |
| `operator` | Ruby operators and related syntax. |

```yaml
styles:
  heading: "fg=#7aa2f7:bold"
  method: "cyan"
  comment: "bright_black"
  link: "blue:underline"
  muted: "none"
```

For a one-off change, use repeatable `--style=ROLE=STYLE` flags:

```sh
rich-ri --theme=dark --style='comment=#9ca3af' --style='method=cyan:bold' Regexp
```

`--format=NAME` selects an original RDoc formatter. Its formatting does not use
rich-ri's theme, role styles or rich page layout.

## Color policy and terminal capability

`color: auto` emits colors only when stdout is a terminal, `NO_COLOR` is empty or
unset, and `TERM` is not `dumb`. `--color` without a value means `always`.
`--color=always` forces colors even in a pipe or with `NO_COLOR` or `TERM=dumb`.
`--no-color` and `--color=never` preserve the page layout without ANSI colors.

Color depth is separate from whether colors are enabled. `color_depth: auto`
uses truecolor when `COLORTERM` is `truecolor` or `24bit`, 256 colors when `TERM`
contains `256color`, and the basic ANSI palette otherwise. Set `basic`, `"256"`
or `truecolor` explicitly to override detection. RGB and palette colors are
approximated when the chosen depth cannot represent them directly.

Ruby examples are highlighted in process and share these styles. No external
highlighter is needed for Ruby or for the rest of the page. Optional bat handles
other explicitly tagged languages and recognized shell commands. Its separate
`bat_theme` and `shell_theme` settings select bat themes; role overrides do not
recolor bat's tokens. Run `bat --list-themes` to see installed themes.

The selected color depth applies to rich-ri's built-in styles; bat handles its
own depth. rich-ri disables bat's configuration file and passes its own formatting
options.
If bat is missing, fails, exceeds two seconds or returns invalid text, the original
code is shown without highlighting and bat is disabled for the rest of the page.
Examples larger than 1 MiB bypass bat; its output is limited to 8 MiB.
Disabling rich-ri colors also disables bat highlighting.

## Environment variables

Empty dedicated `RICH_RI_*` variables are ignored. Unset a variable, or set it to
an empty value, to fall back to the file or an earlier layer.

| Variable | Meaning |
| --- | --- |
| `RICH_RI_CONFIG` | Explicit configuration file path; overridden by `--config` or `--no-config`. |
| `RICH_RI_THEME` | `theme` override. |
| `RICH_RI_COLOR` | `color` override. |
| `RICH_RI_COLOR_DEPTH` | `color_depth` override. |
| `RICH_RI_WIDTH` | `width` override. |
| `RICH_RI_BAT_THEME` | `bat_theme` override; takes precedence over `BAT_THEME`. |
| `RICH_RI_SHELL_THEME` | `shell_theme` override. |
| `RICH_RI_STYLE_<ROLE>` | Override a role using its uppercase name, for example `RICH_RI_STYLE_COMMENT=cyan`. |
| `RI` | Default command-line options, parsed as shell words. |
| `RI_PAGER` | Documentation pager command; overrides the file, below `--pager-command`. |
| `PAGER` | Fallback documentation pager; also used by man according to its own rules. |
| `LESS` | Options for less; rich-ri appends `-R` for its child documentation pager. |
| `BAT_THEME` | Backward-compatible bat theme override when `RICH_RI_BAT_THEME` is unset. |
| `NO_COLOR` | Nonempty values disable automatic colors. |
| `TERM` | `dumb` disables automatic colors; `256color` indicates 256-color capability. |
| `COLORTERM` | `truecolor` or `24bit` indicates truecolor capability in automatic depth mode. |
| `XDG_CONFIG_HOME` | Absolute base directory for the default configuration file. |
| `GEM_HOME`, `GEM_PATH` | RubyGems paths that affect installed documentation stores. |
| `HOME` | Home configuration and RI documentation locations. |
| `PATH` | Search path for external programs such as bat, less and man. |
| `MANPAGER` | Manual viewer's pager, according to man. |
| `MANROFFOPT`, `GROFF_NO_SGR`, `LESS_TERMCAP_*` | Existing manual rendering and palette settings. |
| `MANPATH` | Manual search path for `man rich-ri`. |
| `XDG_DATA_HOME` | Absolute base for `--install-man`; otherwise `~/.local/share` is used. |

For Bash or Zsh, export variables with `export RICH_RI_THEME=light`. In Fish, use
`set -gx RICH_RI_THEME light`. Flags and YAML have the same meaning in all shells.

The bundled manual honors existing man pager and palette settings. rich-ri only
supplies its manual palette when none of those settings are configured. Installing
the manual copies the current bundled file; rerun `--install-man` after upgrades.

## Troubleshooting

- **A configuration error prevents lookup:** run `rich-ri --no-config --show-config`
  to bypass the file, then inspect `rich-ri --config-path`. Dedicated environment
  overrides still apply; correct or unset any invalid one named by the error.
- **A theme appears unchanged:** check `--show-config`, `NO_COLOR`, redirected
  stdout and whether you selected an original RDoc formatter with `--format`.
- **Colors look different over SSH:** check `TERM` and `COLORTERM` in the remote
  session, or select a color depth supported by the actual terminal.
- **Only Ruby examples have colors:** install bat for other languages, and verify
  that `bat_theme` and `shell_theme` name themes listed by `bat --list-themes`.
- **Completion is empty:** run `--show-config` and `--list-doc-dirs`; completion
  uses the same sources and cannot suggest documentation names when configuration
  or stores are invalid. Option and theme suggestions remain available.

Lookup, configuration and usage failures exit with status 1. Interrupts exit with
130; success and a closed output pipe exit with 0. No configuration command edits
shell files or installs completion scripts automatically.
