# frozen_string_literal: true

require_relative "errors"

module RichRI
  # Under the C locale Ruby labels ARGV, ENV and paths BINARY or US-ASCII, RubyGems labels its
  # directories BINARY in any locale, and a UTF-8 string can still hold invalid bytes.
  UNRELIABLE_ENCODINGS = [Encoding::BINARY, Encoding::US_ASCII, Encoding::UTF_8].freeze

  # Every pattern here is UTF-8, and one raises on a BINARY string holding an accent.
  def self.utf8(text)
    text = text.to_s
    return text if text.encoding == Encoding::UTF_8 && text.valid_encoding?
    return text.dup.force_encoding(Encoding::UTF_8).scrub if UNRELIABLE_ENCODINGS.include?(text.encoding)

    text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
  rescue EncodingError
    text.dup.force_encoding(Encoding::UTF_8).scrub
  end

  # Dir.home raises without HOME and a passwd entry; a relative HOME is not relied on.
  def self.home
    home = utf8(Dir.home)
    home if home.start_with?("/")
  rescue ArgumentError
    nil
  end

  def self.home!
    home or raise ConfigurationError, "cannot find a home directory; set HOME to an absolute path"
  end

  # Under the C locale Ruby labels the working and home directories US-ASCII and refuses to
  # join them with an accented name; bytes with an explicit base and home avoid those labels.
  def self.expand_path(path, base = Dir.pwd)
    path = path.b
    path = File.join(home!.b, path[1..]) if path == "~" || path.start_with?("~/")
    utf8(File.expand_path(path, base.b))
  end
end
