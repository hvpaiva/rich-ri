# Reading documentation

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
[security policy](../SECURITY.md) for the trust boundary.

## Manual

`rich-ri --help` lists the options. `rich-ri --man` opens the full manual.
To make the page available through `man rich-ri`, run `rich-ri --install-man`.
The command prints its destination and any needed `MANPATH` setting. Repeat it
when upgrading. Use `--install-man=DIR` to choose another `man1` directory.

## Optional programs

Ruby highlighting is built in. bat adds highlighting for shell commands and
other tagged languages. less, or another RI-compatible pager, provides scrolling
and search. `man` opens the bundled manual. These programs are available from
your operating system's package manager.

Without bat, those code blocks stay plain. If no pager is available, documentation
is written to the terminal; `--no-pager` selects this behavior explicitly.
`--help` and `--install-man` work without the `man` program.

## Exit status

The command exits with 0 on success, 1 for lookup or usage errors and 130 when
interrupted. A closed output pipe is a normal exit.
