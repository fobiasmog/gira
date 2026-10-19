# Resolves which stored file a FilesController URL refers to: the original
# blob, or its preview thumbnail (images and PDFs, rendered with vips and,
# for PDFs, poppler).
module FileVariant
  PREVIEW = { resize_to_limit: [ 400, 400 ], format: :webp }.freeze

  Rendered = Data.define(:bytes, :filename, :content_type) do
    def download = bytes
  end

  module_function

  def for(attachment, variant)
    blob = attachment.blob

    case variant
    when nil then blob
    when "preview"
      raise ActiveRecord::RecordNotFound unless blob.representable?

      Rendered.new(bytes: blob.representation(PREVIEW).processed.download, filename: "preview.webp", content_type: "image/webp")
    else
      raise ActiveRecord::RecordNotFound
    end
  end

  def preview?(blob)
    blob.representable?
  end
end
