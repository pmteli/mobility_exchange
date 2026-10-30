module EquipmentPhotosHelper
  def photo_screening_summary(photo, account_id)
    path = EquipmentMedia::Photos.path(photo.sanitized_object_key)
    screening = PhotoScreening.find_by(account_id: account_id, image_digest: Digest::SHA256.file(path).hexdigest, policy_key: EquipmentMedia::Moderation.policy_key)
    return "Not yet screened with the current policy" unless screening
    labels = screening.labels.map { |label| "#{label['name']} (#{label['confidence'].to_f.round}%)" }.join(", ")
    "#{screening.state.humanize}#{labels.present? ? ': ' + labels : ''}"
  rescue ActiveRecord::RecordNotFound, Errno::ENOENT
    "Photo unavailable"
  end
  def equipment_photos(revision_id)
    ListingPhoto.where(revision_id: revision_id).where.not(sanitized_object_key: [nil, "simulation/equipment-placeholder.png"]).order(:slot)
  end
end
