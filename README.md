# rich-ri

Read Ruby documentation with highlighted code, clear headings and colored
references. rich-ri wraps Ruby's RI reader and uses the documentation already
installed for your Ruby and gems.

![The complete Object#then page: ri -f ansi on the left, rich-ri on the right, with highlighted Ruby method chains, strings, constants and symbols.](docs/images/ri-vs-rich-ri.png)

The same page in `ri -f ansi` and rich-ri, using the same terminal palette.
rich-ri adds Ruby syntax highlighting and keeps heading markers searchable.
[Image details](docs/images/README.md).

## Install and read

Requires Ruby 3.4 or later on Linux or macOS.

```sh
gem install rich-ri
rich-ri Array#map
rich-ri String#scan
```

RDoc, which provides RI, is installed as a gem dependency. If a page is missing,
see [documentation sources](docs/usage.md#documentation-sources-and-missing-pages).

Run `rich-ri` without a name for interactive lookup. Press Tab to discover
classes and methods; enter an empty line to leave. You can also
[enable shell completion](docs/shell-completion.md) for Bash, Zsh or Fish,
and use `ri` as an alias.

## Find your way around

Names follow RI conventions: `Array#map` is an instance method;
`File::open` is a class method. `Class.method` searches both kinds.

```sh
rich-ri Hash
rich-ri --all Array
rich-ri ruby:syntax/pattern_matching
rich-ri --help
```

In less, use `/` to search, `n` for the next match and `q` to quit.
Search for `^=== ` to jump between level-three headings.
`rich-ri --man` opens the full manual.

## Choose your colors

The default colors follow your terminal palette. Ruby highlighting is built in;
installing bat also highlights shell examples and other tagged languages.

```sh
rich-ri --theme=light Regexp
rich-ri --style='comment=bright_black' String#scan
rich-ri --no-color Array#map
```

Save preferences in `~/.config/rich-ri/config.yml`:

```yaml
theme: terminal
styles:
  method: cyan
  comment: bright_black
```

The [configuration reference](docs/configuration.md) covers themes, individual
styles, pager settings and environment variables. `rich-ri --show-config` prints
your effective settings.

## More

- [Reading documentation](docs/usage.md): lookup, pager navigation and your own project's docs.
- [Shell completion and aliases](docs/shell-completion.md).
- [Troubleshooting](docs/troubleshooting.md) and [supported versions](docs/compatibility.md).
- [Contributing](CONTRIBUTING.md): setup, tests and pull requests.
- [Changelog](CHANGELOG.md) and [security policy](SECURITY.md).

Questions and bug reports are welcome in [GitHub issues](https://github.com/hvpaiva/rich-ri/issues).
Released under the [MIT license](LICENSE.txt).
