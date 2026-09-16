require "digest"
# Stores server-generated evidence and photos decoded/re-encoded by DonationPhotos.
class PrivateEvidence
  def self.root
    Pathname.new(ENV.fetch("PRIVATE_STORAGE_PATH", Rails.root.join("storage/private").to_s))
  end
  def self.prepare(bytes, filename, mime)
    key = SecureRandom.uuid
    FileUtils.mkdir_p(root, mode: 0700)
    File.open(root.join(key), File::WRONLY | File::CREAT | File::EXCL, 0600) { |file| file.binmode; file.write(bytes) }
    { object_key: key, original_filename: filename, mime_type: mime, byte_size: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes), scan_status: "clean" }
  end
  def self.persist!(attributes, actor)
    StoredFile.create!(attributes.merge(uploaded_by: actor.id))
  end
  def self.path(record)
    raise ActiveRecord::RecordNotFound unless record.object_key.match?(/\A[0-9a-f-]{36}\z/) && record.deleted_at.nil?
    file = root.join(record.object_key)
    raise ActiveRecord::RecordNotFound unless file.file? && Digest::SHA256.file(file).hexdigest == record.sha256
    file
  end
end
