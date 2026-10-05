# frozen_string_literal: true

# Text from a repository or an argument must reach the terminal as text: an escape sequence
# would otherwise act on it. Line breaks stay, since a message may span lines.
module Untrusted
  def self.visible(text) = text.gsub(/[[:cntrl:]&&[^\n]]/) { |character| character.dump[1..-2] }
end
