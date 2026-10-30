require "timeout"
module EquipmentMedia
  class Photos
    MAX_BYTES = 5.megabytes
    def self.root
      Rails.root.join("storage", Rails.env.test? ? "test_equipment_photos" : "equipment_photos")
    end
    def self.path(key)
      raise ActiveRecord::RecordNotFound unless key.to_s.match?(/\A[0-9a-f-]{36}\.jpg\z/)
      root.join(key)
    end
    def self.prepare(upload)
      unless upload.respond_to?(:tempfile) && upload.size.between?(1, MAX_BYTES)
        raise Journeys::Error, "Each photo must be a JPEG or PNG no larger than 5 MB."
      end
      header = File.binread(upload.tempfile.path, 8)
      unless header.start_with?("\xff\xd8\xff".b) || header == "\x89PNG\r\n\x1a\n".b
        raise Journeys::Error, "Only JPEG and PNG photos are supported."
      end
      FileUtils.mkdir_p(root)
      key = "#{SecureRandom.uuid}.jpg"
      output = path(key)
      pid = Process.spawn("python3", Rails.root.join("script/sanitize_equipment_photo.py").to_s, upload.tempfile.path, output.to_s, out: File::NULL, err: File::NULL)
      begin
        _, status = Timeout.timeout(20) { Process.wait2(pid) }
      rescue Timeout::Error
        Process.kill("KILL", pid) rescue nil
        Process.wait(pid) rescue nil
        raise Journeys::Error, "This photo took too long to process. Try a smaller image."
      end
      unless status.success? && output.file? && output.size.between?(1, MAX_BYTES)
        raise Journeys::Error, "Unable to read this photo. Use a valid, non-animated JPEG or PNG up to 25 megapixels."
      end
      {sanitized_object_key: key, mime_type: "image/jpeg", byte_size: output.size, metadata_stripped_at: Time.current, state: "processing"}
    rescue SystemCallError
      FileUtils.rm_f(output) if output
      raise Journeys::Error, "Photo storage is temporarily unavailable. Your listing has not been submitted; please try again."
    rescue StandardError
      FileUtils.rm_f(output) if output
      raise
    end
    def self.copy(photo)
      photo.attributes.slice("sanitized_object_key", "mime_type", "byte_size", "metadata_stripped_at").symbolize_keys.merge(state: "processing")
    end
  end
end
