require "test_helper"
class JourneysTest < ActionDispatch::IntegrationTest
  setup { Rails.cache.clear }
  def sign_in(user)
    otp = nil
    if user.admin?
      secret = ROTP::Base32.random
      Workflow.run { user.credential.reload.update!(mfa_secret: secret, last_otp_at: nil) }
      otp = ROTP::TOTP.new(secret).now
    end
    post session_path, params: { email: user.email, password: "correct horse battery staple", otp: otp }
    assert_redirected_to account_path
  end
  def publish_document(actor, kind)
    Workflow.run do
      text = "TEST DOCUMENT ONLY. Equipment is provided under the terms reviewed here."
      version = LegalDocumentVersion.create!(kind: kind, version: SecureRandom.hex(8), title: "Test document", exact_text: text, text_sha256: Digest::SHA256.hexdigest(text), published_at: Time.current, published_by: actor.id)
      active = ActiveLegalDocument.find_or_initialize_by(kind: kind)
      active.update!(version_id: version.id)
      version
    end
  end
  test "request through signed pickup and protected PDF download" do
    admin, owner, outsider = create_user(role: "admin"), create_user, create_user
    item = make_available(admin, create_item(admin))
    version = publish_document(admin, "recipient_waiver")
    sign_in(owner)
    get new_equipment_request_path(equipment_id: item.id)
    assert_response :success
    post equipment_requests_path, params: { equipment_id: item.id, contact: { phone: "555-0100" } }
    assert_response :redirect
    request = EquipmentRequest.find_by!(requested_by: owner.id)
    get equipment_request_path(request)
    assert_response :success
    post sign_equipment_request_path(request), params: { version_id: version.id, signature: owner.name, consent: "1" }
    assert_response :redirect
    signed = request.signed_waivers.first!
    get document_path(signed.signed_pdf_file_id)
    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert response.body.start_with?("%PDF")
    assert_raises(Workflow::Error) { Workflow.run { signed.update!(signer_name: "Changed") } }
    sign_in(outsider)
    get document_path(signed.signed_pdf_file_id)
    assert_response :not_found
    sign_in(admin)
    patch staff_request_path(request), params: { status: "approved" }
    assert_response :redirect
    post reserve_staff_request_path(request)
    assert_response :redirect
    get staff_request_path(request)
    assert_response :success
    slot = Workflow.run { AppointmentSlot.create!(location_id: item.location_id, kind: "pickup", starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour, capacity: 1, created_by: admin.id) }
    sign_in(owner)
    post book_equipment_request_path(request), params: { slot_id: slot.id }
    assert_response :redirect
    sign_in(admin)
    post release_staff_request_path(request), params: { reservation_id: request.reservations.first!.id, signature: owner.name, condition: "Good; recipient accepted equipment" }
    assert_response :redirect
    assert_equal "distributed", item.reload.status_code
    assert_equal "completed", request.reload.status
    assert_equal "completed", Appointment.find_by!(request_id: request.id).status
    assert_equal "fulfilled", request.reservations.first.status
  end
  test "donation is reviewed signed booked and received once per physical unit" do
    admin, donor = create_user(role: "admin"), create_user
    item = create_item(admin)
    version = publish_document(admin, "donor_certification")
    sign_in(donor)
    get new_donation_path
    assert_response :success
    post donations_path, params: { contact: { phone: "555-0100" }, item: { type_id: item.type_id, name: "Donated walker", condition: "good", quantity: 1 } }
    assert_response :redirect
    donation = IntakeSubmission.find_by!(submitted_by: donor.id)
    post sign_donation_path(donation), params: { version_id: version.id, signature: donor.name, consent: "1" }
    assert_response :redirect
    get donation_path(donation)
    assert_response :success
    sign_in(admin)
    patch staff_donation_path(donation), params: { status: "approved" }
    assert_response :redirect
    slot = Workflow.run { AppointmentSlot.create!(location_id: item.location_id, kind: "dropoff", starts_at: 2.days.from_now, ends_at: 2.days.from_now + 1.hour, capacity: 1, created_by: admin.id) }
    sign_in(donor)
    post book_donation_path(donation), params: { slot_id: slot.id }
    assert_response :redirect
    sign_in(admin)
    line = donation.intake_items.first!
    post receive_item_staff_donation_path(donation), params: { item_id: line.id, location_id: item.location_id }
    assert_response :redirect
    assert_equal "completed", donation.reload.status
    assert_equal 1, Equipment.where(intake_item_id: line.id).count
    post receive_item_staff_donation_path(donation), params: { item_id: line.id, location_id: item.location_id }
    assert_response :unprocessable_entity
    assert_equal 1, Equipment.where(intake_item_id: line.id).count
  end
  test "staff forms and reports render and schedules persist" do
    admin = create_user(role: "admin")
    item = create_item(admin)
    page = Workflow.run { ContentPage.create!(slug: "test-#{SecureRandom.hex(8)}", title: "Test page", body_markdown: "<script>alert('escaped')</script>", updated_by: admin.id, published_at: Time.current) }
    sign_in(admin)
    [staff_root_path, staff_equipment_index_path, new_staff_equipment_path, edit_staff_equipment_path(item), staff_equipment_path(item), staff_requests_path, staff_donations_path, staff_volunteers_path, staff_shifts_path, new_staff_shift_path, staff_slots_path, new_staff_slot_path, staff_pages_path, edit_staff_page_path(page), staff_reports_path, account_path, shifts_path, new_volunteer_application_path].each do |path|
      get path
      assert_response :success, path
    end
    get staff_reports_path(format: :csv)
    assert_response :success
    assert_includes response.body, "Status,Units"
    get page_path(page.slug)
    assert_response :success
    assert_not_includes response.body, "<script>alert"
    post staff_shifts_path, params: { schedule: { activity: "Inspection shift", location_id: item.location_id, starts_at: 3.days.from_now.iso8601, ends_at: (3.days.from_now + 1.hour).iso8601, capacity: 2 } }
    assert_response :redirect
    post staff_slots_path, params: { schedule: { kind: "pickup", location_id: item.location_id, starts_at: 3.days.from_now.iso8601, ends_at: (3.days.from_now + 1.hour).iso8601, capacity: 2 } }
    assert_response :redirect
  end
  test "verification email renders and activation consumes token" do
    user = Signup.call(community_roles: ["donor"], email: "verify-#{SecureRandom.hex(8)}@example.test", first_name: "Test", last_name: "Account", password: "correct horse battery staple", password_confirmation: "correct horse battery staple")
    notification = Notification.find_by!(recipient_user_id: user.id)
    mail = AccountMailer.notification(notification)
    assert_includes mail.text_part.body.decoded, "Verify your email"
    assert_includes mail.html_part.body.decoded, "Verify email address"
    token = notification.payload_json.fetch("token")
    get verification_path(token)
    assert_response :success
    post verification_path(token)
    assert_response :redirect
    assert_equal "active", user.reload.account_status
    assert_nil AccountTokens.resolve(token, "verify")
  end
  test "invalid schedules return validation errors without writing" do
    admin = create_user(role: "admin")
    item = create_item(admin)
    sign_in(admin)
    assert_no_difference "AppointmentSlot.count" do
      post staff_slots_path, params: { schedule: { location_id: item.location_id, kind: "pickup", starts_at: "", ends_at: "", capacity: 0 } }
      assert_response :unprocessable_entity
    end
  end
  test "pending users can request another verification link" do
    user = create_user(verified: false)
    get new_verification_request_path
    assert_response :success
    assert_difference "Notification.where(recipient_user_id: user.id).count", 1 do
      post verification_request_path, params: { email: user.email }
      assert_response :redirect
    end
  end
  test "outbox worker delivers and marks account email sent" do
    user = Signup.call(community_roles: ["donor"], email: "mail-#{SecureRandom.hex(8)}@example.test", first_name: "Mail", last_name: "Test", password: "correct horse battery staple", password_confirmation: "correct horse battery staple")
    notification = Notification.find_by!(recipient_user_id: user.id)
    Workflow.run { notification.update!(created_at: 50.years.ago, available_at: 1.minute.ago) }
    assert_difference "ActionMailer::Base.deliveries.count", 1 do
      assert NotificationDelivery.deliver_one
    end
    assert_equal "sent", notification.reload.status
    assert_equal 1, notification.attempts
  end
end
