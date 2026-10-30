module JourneysHelper
  def revision_for(listing)
    ListingRevision.find(listing.current_revision_id)
  end
  def local_text(ciphertext)
    Journeys::Support.decrypt(ciphertext)
  end
end
