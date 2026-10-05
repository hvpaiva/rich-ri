# frozen_string_literal: true

require_relative "errors"

module RichRI
  # Labels that say nothing reliable about a string's characters. Under the C
  # locale Ruby hands over ARGV, ENV and paths as BINARY or US-ASCII, RubyGems
  # labels its directories BINARY in any locale, and a UTF-8 string can still
  # hold invalid bytes.
  UNRELIABLE_ENCODINGS = [Encoding::BINARY, Encoding::US_ASCII, Encoding::UTF_8].freeze

  # Reads text from outside the program as UTF-8, which every pattern here
  # assumes: a UTF-8 pattern raises on a BINARY string holding one accent.
  # Bytes without a trustworthy label are taken as UTF-8, keeping the valid
  # ones and replacing the rest; text in a declared encoding is converted.
  def self.utf8(text)
    text = text.to_s
    return text if text.encoding == Encoding::UTF_8 && text.valid_encoding?
    return text.dup.force_encoding(Encoding::UTF_8).scrub if UNRELIABLE_ENCODINGS.include?(text.encoding)

    text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
  rescue EncodingError
    text.dup.force_encoding(Encoding::UTF_8).scrub
  end

  # The user's home directory as UTF-8, or nil when there is none to rely on:
  # HOME is unset for a user without a passwd entry, or is not an absolute path.
  def self.home
    home = utf8(Dir.home)
    home if home.start_with?("/")
  rescue ArgumentError
    nil
  end

  def self.home!
    home or raise ConfigurationError, "cannot find a home directory; set HOME to an absolute path"
  end

  # File.expand_path as UTF-8. It cannot be given the name directly: under the
  # C locale Ruby labels the working and home directories US-ASCII and refuses
  # to join them with any other string holding an accent. Joining bytes with an
  # explicit base and home directory never consults those labels.
  def self.expand_path(path, base = Dir.pwd)
    path = path.b
    path = File.join(home!.b, path[1..]) if path == "~" || path.start_with?("~/")
    utf8(File.expand_path(path, base.b))
  end
end
