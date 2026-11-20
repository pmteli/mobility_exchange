require "test_helper"
require Rails.root.join("db/seeds/journeys")

class LiveJourneysTest < ActionDispatch::IntegrationTest
  setup do
    load Rails.root.join("db/seeds.rb")
    JourneySeeds.load!
    @donor = Account.find(JourneySeeds.id(1))
    @recipient = Account.find(JourneySeeds.id(3))
    @moderator = Account.find(JourneySeeds.id(5))
    @listing = Listing.find(JourneySeeds.id(1000))
  end
  def login(n)
    return login_staff_account(Account.find(JourneySeeds.id(n))) if Staff::Authentication.staff?(Account.find(JourneySeeds.id(n)))
    delete sign_out_path
    post sign_in_path, params: {mobile: "+1510555010#{n}"}
    assert_redirected_to verify_sign_in_path
    code = SimulatedSmsMessage.where(recipient: "+1510555010#{n}", template_code: "sign_in_otp").order(created_at: :desc).first!.body[/code: (\d+)/, 1]
    post verify_sign_in_path, params: {code: code}
    assert_response :redirect
  end
  def publish(listing = @listing)
    Journeys::Workflow.new(@moderator).review!(listing.id, "approve", "Fictional test review")
    listing.reload
  end
  def request_item(listing = @listing)
    Journeys::Workflow.new(@recipient).request!(listing.id, consent: "1", outcome: "pass")
  end
  def approve(exchange)
    Journeys::Workflow.new(@donor).change!(exchange.id, "approve", meeting_at: 2.days.from_now.strftime("%Y-%m-%dT12:00"), location: "Sample public library")
  end
  test "donors and recipients can disable SMS while simulation is active" do
    [1, 3].each do |number|
      login(number)
      get my_account_path
      assert_select "h2", text: "SMS Preferences"
      assert_select "#sms-preferences form[action=?]", sms_preferences_path
      patch sms_preferences_path, params: {sms_consent: "1"}
      assert_redirected_to my_account_path(anchor: "sms-preferences")
      get my_account_path
      assert_select "#sms-preferences input[name=sms_consent][checked]", count: 1
      patch sms_preferences_path, params: {sms_consent: "0"}
      assert_redirected_to my_account_path(anchor: "sms-preferences")
      get my_account_path
      assert_select "#sms-preferences input[name=sms_consent][checked]", count: 0
      contact = AccountContact.find_by!(account_id: JourneySeeds.id(number), kind: "mobile", revoked_at: nil)
      refute Integrations::SmsConsent.allowed?(contact.lookup_hmac)
    end
  end

  test "equipment back link returns owners to activity and moderators to reviews" do
    login(5)
    get equipment_path(@listing)
    assert_response :success
    assert_select "a.back[href=?]", activity_path(anchor: "panel-review"), text: "← Back to Listing Reviews"
    login(1)
    get equipment_path(@listing)
    assert_select "a.back[href=?]", activity_path, text: "← Back to My Activity"
    publish
    login(3)
    get equipment_path(@listing)
    assert_select "a.back[href=?]", equipment_index_path, text: "← Back to equipment"
    delete sign_out_path
    get equipment_path(@listing)
    assert_select "a.back[href=?]", equipment_index_path, text: "← Back to equipment"
  end

  test "OTP sign-in role permissions and private pages" do
    login(3)
    get activity_path
    assert_response :success
    assert_select "h1", text: "Hello, Maya Patel"
    post review_listing_path(@listing), params: {decision: "approve", reason: "forged"}
    assert_equal "pending_review", @listing.reload.status
    get edit_listing_path(@listing)
    assert_response :redirect
    delete sign_out_path
    get activity_path
    assert_redirected_to sign_in_path
  end
  test "failed and reused OTP codes cannot grant a session" do
    post sign_in_path, params: {mobile: "+15105550103"}
    code = SimulatedSmsMessage.where(template_code: "sign_in_otp").order(created_at: :desc).first!.body[/code: (\d+)/, 1]
    bad = code == "000000" ? "111111" : "000000"
    3.times { post verify_sign_in_path, params: {code: bad}; assert_response :unprocessable_entity }
    post verify_sign_in_path, params: {code: code}
    assert_response :unprocessable_entity
    get activity_path
    assert_redirected_to sign_in_path
  end
  test "gift journey persists proposals identity visibility and exactly one handoff" do
    publish
    exchange = request_item
    approve(exchange)
    login(1)
    get transaction_path(exchange)
    assert_response :success
    assert_includes response.body, "Maya"
    refute_includes response.body, "FICTIONAL ADDRESS"
    proposal = HandoffProposal.find_by!(exchange_id: exchange.id)
    recipient_flow = Journeys::Workflow.new(@recipient)
    recipient_flow.change!(exchange.id, "propose", proposal_id: proposal.id, meeting_at: 3.days.from_now.strftime("%Y-%m-%dT12:00"), location: "Another public library")
    assert_equal "reserved", exchange.reload.state
    latest = HandoffProposal.where(exchange_id: exchange.id).order(revision: :desc).first!
    assert_raises(Journeys::Error) { Journeys::Workflow.new(@donor).change!(exchange.id, "accept", proposal_id: proposal.id) }
    Journeys::Workflow.new(@donor).change!(exchange.id, "accept", proposal_id: latest.id)
    recipient_flow.change!(exchange.id, "handoff")
    assert_equal "completed", exchange.reload.state
    assert_equal "donated", @listing.reload.status
    assert_raises(Journeys::Error) { recipient_flow.change!(exchange.id, "handoff") }
    assert_equal 1, ExchangeEvent.where(exchange_id: exchange.id, event_type: "handoff_confirmed").count
    assert SimulatedSmsMessage.where(template_code: "handoff_proposed").exists?
  end
  test "failed identity and competing request do not notify or allocate twice" do
    publish
    failed = Journeys::Workflow.new(@recipient).request!(@listing.id, consent: "1", outcome: "fail")
    assert_equal "failed", failed.state
    assert_equal 0, Exchange.where(listing_id: @listing.id).count
    refute SimulatedSmsMessage.where(template_code: "request_received").exists?
    exchange = request_item
    other = Journeys::Workflow.new(Account.find(JourneySeeds.id(4)))
    assert_raises(Journeys::Error) { other.request!(@listing.id, consent: "1", outcome: "pass") }
    assert_raises(Journeys::Error) { other.change!(exchange.id, "decline") }
    assert_equal 1, Exchange.where(listing_id: @listing.id).count
  end
  test "loan handoff blocks revoke and allows recipient return before donor reopening" do
    loan = Listing.find(JourneySeeds.id(1004))
    publish(loan)
    exchange = request_item(loan)
    approve(exchange)
    proposal = HandoffProposal.find_by!(exchange_id: exchange.id)
    recipient_flow = Journeys::Workflow.new(@recipient)
    recipient_flow.change!(exchange.id, "accept", proposal_id: proposal.id)
    Journeys::Workflow.new(@donor).change!(exchange.id, "handoff")
    assert_equal "loaned", exchange.reload.state
    assert_raises(Journeys::Error) { recipient_flow.change!(exchange.id, "revoke") }
    recipient_flow.change!(exchange.id, "return")
    assert_equal "loan_return_confirmed", exchange.reload.retention_end_reason
    donor_flow = Journeys::Workflow.new(@donor)
    assert_raises(Journeys::Error) { donor_flow.change!(exchange.id, "return") }
    assert_equal "unavailable", loan.reload.status
    donor_flow.reopen!(loan.id, "1")
    assert_equal "available", loan.reload.status
  end
  test "expiry closure retry and seven day followup" do
    publish
    exchange = request_item
    travel 49.hours do
      Journeys::Deadlines.run!
      assert_equal "expired", exchange.reload.state
      Journeys::Workflow.new(@donor).reopen!(@listing.id, "1")
      replacement = Journeys::Workflow.new(@recipient).request!(@listing.id, consent: "1", outcome: "pass", retry_id: exchange.id)
      assert ExchangeDisplayPreference.find_by!(exchange_id: exchange.id).hidden_at
      approve(replacement)
      proposal = HandoffProposal.find_by!(exchange_id: replacement.id)
      Journeys::Workflow.new(@recipient).change!(replacement.id, "accept", proposal_id: proposal.id)
      # PostgreSQL's clock is real; explicitly pass the simulated due date to the queue function.
      as_of = replacement.reload.reserved_at + 8.days
      2.times { ApplicationRecord.connection.execute(ApplicationRecord.sanitize_sql_array(["SELECT freedme.enqueue_handoff_followups(?)", as_of])) }
      assert_equal 1, ModeratorTask.where(exchange_id: replacement.id).count
      assert_equal "reserved", replacement.reload.state
    end
  end
  test "registration rejects unsupported locations before issuing a code" do
    ["Los Angeles", "90001", "Sacramento", "95814", "Los Angeles · 94536", "Fremont · 90001"].each do |locality|
      assert_no_difference ["Account.count", "AuthChallenge.count", "SimulatedSmsMessage.count"] do
        post register_path, params: {mobile: "5105550199", display_name: "Tester", locality: locality}
      end
      assert_response :unprocessable_entity
      assert_includes response.body, "FreeDME is currently available only for Bay Area, California community members"
    end
  end

  test "registration rechecks location before account creation" do
    pending = Journeys::Authentication.start!(mobile: "5105550199", name: "Tester", locality: "94536", registration: true)
    code = SimulatedSmsMessage.where(recipient: "+15105550199", template_code: "sign_in_otp").order(created_at: :desc).first!.body[/code: (\d+)/, 1]
    pending["locality"] = "90001"
    assert_no_difference "Account.count" do
      assert_raises(Journeys::Error) { Journeys::Authentication.verify!(pending, code) }
    end
    assert_nil AuthChallenge.find(pending["challenge_id"]).consumed_at
  end

  test "new registration and question answer persist" do
    post register_path, params: {mobile: "5105550111", display_name: "New Tester", locality: "Newark"}
    refute Account.exists?(display_name: "New Tester")
    refute SimulatedSmsMessage.where(template_code: "registration_welcome", recipient: "+15105550111").exists?
    code = SimulatedSmsMessage.where(template_code: "sign_in_otp").order(created_at: :desc).first!.body[/code: (\d+)/, 1]
    post verify_sign_in_path, params: {code: code}
    account = Account.find_by!(display_name: "New Tester")
    welcome = SimulatedSmsMessage.where(template_code: "registration_welcome", recipient: "+15105550111")
    assert_equal 1, welcome.count
    assert_equal "Welcome to FreeDME New Tester. Take the next step to either donate, lend or find a mobility equipment for yourself or your loved ones. Visit #{Integrations::SmsLinks.url("registration_welcome")}", welcome.first!.body
    assert_equal "/s/home", URI.parse(Integrations::SmsLinks.url("registration_welcome")).path
    assert AccountContact.where(account_id: account.id).where.not(verified_at: nil).exists?
    publish
    post equipment_questions_path(@listing), params: {question: "Does it fold?"}
    question = EquipmentQuestion.find_by!(requester_id: account.id)
    Journeys::Workflow.new(@donor).answer!(question.id, "Yes, it folds.")
    get activity_path
    assert_response :success
    assert_includes response.body, "Yes, it folds."
    assert SimulatedSmsMessage.where(template_code: "question_answered").exists?
  end
  test "donor creates and edits listing and moderator publishes through controllers" do
    login(1)
    get new_listing_path
    assert_response :success
    data = { title: "HTTP sample cane", description: "Fictional folding cane", category_id: Category.find_by!(code: "canes").id,
      public_locality: "Fremont", condition_code: "new", offer_kind: "gift", pickup_availability: "Library at noon",
      no_missing_parts_affirmed: "1", fully_functional_affirmed: "1", truthfulness_affirmed: "1" }
    post listings_path, params: {listing: data.merge(title: "")}
    assert_response :unprocessable_entity
    assert_includes response.body, "Fictional folding cane"
    post listings_path, params: {listing: data.merge(photos: [Rack::Test::UploadedFile.new(Rails.root.join("public/simulation/equipment-placeholder.png"), "image/png")])}
    assert_redirected_to activity_path(anchor: "panel-inventory")
    listing = Listing.where(donor_id: @donor.id).newest_first.first!
    assert_equal "pending_review", listing.status
    assert ListingReviewAlert.exists?(account_id: @moderator.id, revision_id: listing.current_revision_id)
    patch update_listing_path(listing), params: {listing: data.merge(title: "Revised sample cane")}
    assert_redirected_to activity_path(anchor: "panel-inventory")
    assert_equal 2, listing.revisions.count
    login(5)
    get activity_path
    assert_response :success
    post review_listing_path(listing), params: {decision: "approve", reason: "Simulation only"}
    assert_equal "available", listing.reload.status
    get equipment_path(listing)
    assert_response :success
    assert_includes response.body, "Revised sample cane"
  end

  test "recipient submits request through controller and outsider cannot view it" do
    publish
    login(3)
    get new_equipment_request_path(@listing)
    assert_response :success
    post equipment_request_path(@listing), params: {consent: "1", outcome: "pass"}
    exchange = Exchange.find_by!(listing_id: @listing.id)
    get transaction_path(exchange)
    assert_response :success
    login(4)
    get transaction_path(exchange)
    assert_response :redirect
    assert_not_includes response.body, "Maya Patel"
  end

  test "sign in and registration forms and endpoints are separate" do
    get sign_in_path
    assert_select "input[name=mobile]", count: 1
    assert_select "input[name=display_name]", count: 0
    assert_select "input[name=locality]", count: 0
    post sign_in_path, params: {mobile: "5105550122", display_name: "Injected name", locality: "Fremont"}
    assert_redirected_to register_path
    assert_nil session[:pending_login]
    follow_redirect!
    assert_select "input[name=mobile][value='5105550122']"
    assert_select "input[name=display_name][required]"
    assert_select "input[name=locality][required]"
    refute Account.exists?(display_name: "Injected name")
    post register_path, params: {mobile: "5105550101", display_name: "Duplicate", locality: "Newark"}
    assert_response :unprocessable_entity
    assert_includes response.body, "already registered"
    refute Account.exists?(display_name: "Duplicate")
    post register_path, params: {mobile: "5105550122", display_name: "", locality: ""}
    assert_response :unprocessable_entity
  end

end
