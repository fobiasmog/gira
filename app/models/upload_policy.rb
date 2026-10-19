# Checks an uploaded file against a size limit and a content-type allowlist.
# The type is sniffed from the file's bytes only, never from the client's
# filename or Content-Type, so an SVG renamed to avatar.png is still an SVG
# (design.md, Decision 12).
class UploadPolicy
  attr_reader :types, :max_size

  def initialize(types:, max_size:)
    @types = types
    @max_size = max_size
  end

  # Returns nil when the file is acceptable, otherwise :too_large,
  # :content_type_not_allowed or :blank.
  def violation(file)
    return :blank unless file.respond_to?(:size) && file.respond_to?(:read)
    return :too_large if file.size > max_size
    :content_type_not_allowed unless types.include?(self.class.sniff(file))
  end

  # The type from the bytes alone. Text without a recognisable signature is
  # text/plain only if it is valid UTF-8 with no control characters.
  def self.sniff(file)
    io = file.respond_to?(:tempfile) ? file.tempfile : file
    io.rewind
    type = Marcel::MimeType.for(io)
    type == "application/octet-stream" && plain_text?(io) ? "text/plain" : type
  ensure
    io&.rewind
  end

  def self.plain_text?(io)
    io.rewind
    sample = io.read(64.kilobytes).to_s.dup.force_encoding(Encoding::UTF_8)
    sample.valid_encoding? && !sample.match?(/[\x00-\x08\x0E-\x1F\x7F]/)
  end
end
