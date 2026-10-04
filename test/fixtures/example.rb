# frozen_string_literal: true

# = Example documentation
#
# Discover RichRIExample#map and +RichRIExample+ from your terminal.
#
# == Working with values
#
# * Iterate with a block.
# * Keep the original values intact.
#
#   values = [:one, 2, "hello"]
#   values.map { |value| value.to_s }
#
# === Command and output
#
#   $ echo "hello" | ruby -e 'puts STDIN.read'
#   hello
#
# See {Ruby}[https://www.ruby-lang.org/] for more information.
class RichRIExample
  # Return transformed values.
  #
  #   example.map { |value| value.to_s }
  #
  # :call-seq:
  #   map { |value| block } -> Array
  def map
    yield 1
  end

  # Create an example.
  def self.build
    new
  end

  # A nested example for namespace discovery.
  class Nested
  end
end
