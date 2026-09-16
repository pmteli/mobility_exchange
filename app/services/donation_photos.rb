require "open3"
require "tempfile"

class DonationPhotos
  MAX_SIZE = 5.megabytes

  def self.prepare(uploads)
    uploads = Array(uploads).reject(&:blank?)
    raise Workflow::Error, "Choose no more than three equipment photos." if uploads.length > 3
    prepared = []
    uploads.each_with_index do |upload, index|
      unless upload.respond_to?(:tempfile) && upload.size.between?(1, MAX_SIZE)
        raise Workflow::Error, "Each photo must be a JPEG or PNG file no larger than 5 MB."
      end
      signature = File.binread(upload.tempfile.path, 8)
      coder = if signature.start_with?("\xFF\xD8\xFF".b) then "jpeg"
        elsif signature == "\x89PNG\r\n\x1A\n".b then "png"
        end
      raise Workflow::Error, "Only JPEG and PNG photos are supported." unless coder
      # Force the decoder and re-encode pixels, stripping metadata and embedded content.
      Tempfile.create(["donation-photo", ".jpg"]) do |output|
        _, _, status = Open3.capture3("convert", "-limit", "thread", "1", "-limit", "memory", "64MiB",
          "-limit", "map", "128MiB", "-limit", "disk", "128MiB", "-limit", "time", "15",
          "#{coder}:#{upload.tempfile.path}[0]", "-auto-orient", "-thumbnail", "1600x1600>",
          "-background", "white", "-alpha", "remove", "-strip", "-quality", "85", "jpeg:#{output.path}")
        raise Workflow::Error, "A photo could not be read. Choose a valid JPEG or PNG image." unless status.success? && File.size?(output.path)
        prepared << PrivateEvidence.prepare(File.binread(output.path), "equipment-photo-#{index + 1}.jpg", "image/jpeg")
      end
    end
    prepared
  rescue StandardError
    cleanup(prepared || [])
    raise
  end

  def self.cleanup(files)
    files.each { |file| FileUtils.rm_f(PrivateEvidence.root.join(file.fetch(:object_key))) }
  end
end
