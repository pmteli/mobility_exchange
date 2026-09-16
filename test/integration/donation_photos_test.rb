require "test_helper"
class DonationPhotosTest < ActionDispatch::IntegrationTest
  def upload
    Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/equipment.png"), "image/png")
  end
  def attrs(actor)
    {type_id: create_item(actor).type_id, name: "Photo test walker", condition: "good", quantity: 1}
  end
  test "donor can submit three photos and only owner and reviewers can read them" do
    donor = create_user
    post session_path, params: {email: donor.email, password: "correct horse battery staple"}
    post donations_path, params: {contact: {city: "San Jose"}, item: attrs(donor), photos: [upload, upload, upload]}
    assert_response :redirect
    donation = IntakeSubmission.find_by!(submitted_by: donor.id)
    photos = donation.intake_items.first.photos
    assert_equal 3, photos.count
    get donation_path(donation)
    assert_select ".donation-photos img", 3
    path = donation_photo_path(donation, photos.first)
    get path
    assert_response :success
    assert_equal "image/jpeg", response.media_type
    assert_includes response.headers["Cache-Control"], "private"
    other = create_user
    post session_path, params: {email: other.email, password: "correct horse battery staple"}
    get path
    assert_response :not_found
    reviewer = create_user(role: "volunteer")
    post session_path, params: {email: reviewer.email, password: "correct horse battery staple"}
    get path
    assert_response :success
    delete session_path
    get path
    assert_redirected_to new_session_path
  end
  test "optional photos and invalid uploads are handled without partial records" do
    donor = create_user
    item = attrs(donor)
    assert_difference "IntakeSubmission.count", 1 do
      SubmitDonation.call(donor, {}, item)
    end
    assert_no_difference ["IntakeSubmission.count", "StoredFile.count"] do
      assert_raises(Workflow::Error) { SubmitDonation.call(donor, {}, item, photos: [upload]*4) }
      invalid = Rack::Test::UploadedFile.new(Rails.root.join("Gemfile"), "image/jpeg")
      assert_raises(Workflow::Error) { SubmitDonation.call(donor, {}, item, photos: [upload, invalid]) }
      large = upload
      large.define_singleton_method(:size) { 6.megabytes }
      assert_raises(Workflow::Error) { SubmitDonation.call(donor, {}, item, photos: [large]) }
    end
  end
end
