# Generated image files for upload tests.
module ImageFiles
  def image_upload(format:, width: 600, height: 400, filename: "image.#{format}", noise: false)
    image = noise ? Vips::Image.gaussnoise(width, height).cast(:uchar).bandjoin([ Vips::Image.gaussnoise(width, height).cast(:uchar) ] * 2) :
      Vips::Image.black(width, height, bands: 3).new_from_image([ 30, 120, 200 ]).cast(:uchar)
    file_upload(image.write_to_buffer(".#{format}", **(format == "jpg" ? { Q: 100 } : {})), filename, "image/#{format}")
  end

  def file_upload(bytes, filename, declared_type)
    tempfile = Tempfile.new([ "upload", File.extname(filename) ], binmode: true)
    tempfile.write(bytes)
    tempfile.rewind
    Rack::Test::UploadedFile.new(tempfile.path, declared_type, true, original_filename: filename)
  end
end

module PdfFiles
  # A valid one-page PDF, padded with an unused stream to reach a size.
  def pdf_bytes(padding: 0)
    content = "0 0 1 rg 20 20 160 160 re f"
    objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R >>",
      "<< /Length #{content.bytesize} >>\nstream\n#{content}\nendstream",
      "<< /Length #{padding} >>\nstream\n#{"x" * padding}\nendstream"
    ]
    pdf = +"%PDF-1.4\n"
    offsets = objects.each_with_index.map do |object, index|
      pdf.bytesize.tap { pdf << "#{index + 1} 0 obj\n#{object}\nendobj\n" }
    end
    xref = pdf.bytesize
    pdf << "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n"
    offsets.each { |offset| pdf << format("%010d 00000 n \n", offset) }
    pdf << "trailer\n<< /Size #{objects.size + 1} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n"
  end
end
