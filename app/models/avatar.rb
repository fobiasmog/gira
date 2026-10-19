# Avatar images: a generated default for new accounts, and re-encoding of
# uploads to at most 256×256 WebP (spec user-profile, "Avatar").
module Avatar
  SIZE = 256
  UPLOAD_POLICY = UploadPolicy.new(types: %w[image/png image/jpeg image/webp], max_size: 5.megabytes)
  # Refuse decompression bombs before decoding pixels.
  MAX_PIXELS = 40_000_000

  class InvalidImage < StandardError; end

  module_function

  def default_png
    color = Array.new(3) { rand(60..200) }
    image = Vips::Image.black(SIZE, SIZE, bands: 3).new_from_image(color).cast(:uchar)
    image.write_to_buffer(".png")
  end

  def reencode(file)
    data = file.read
    source = Vips::Image.new_from_buffer(data, "")
    raise InvalidImage if source.width * source.height > MAX_PIXELS

    Vips::Image.thumbnail_buffer(data, SIZE, height: SIZE, size: :down)
      .autorot.write_to_buffer(".webp", Q: 85, strip: true)
  rescue Vips::Error
    raise InvalidImage
  end
end
