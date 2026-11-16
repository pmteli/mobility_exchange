require 'test_helper'
require Rails.root.join('db/seeds/journeys')
class MyAccountTest < ActionDispatch::IntegrationTest
  setup do
    load Rails.root.join('db/seeds.rb')
    JourneySeeds.load!
    @account = Account.find(JourneySeeds.id(1))
    @phone = '+15105550101'
    @new_phone = '+15105550999'
  end
  def code(phone)
    SimulatedSmsMessage.where(recipient: phone, template_code: 'sign_in_otp').order(created_at: :desc).first!.body[/code: (\d+)/, 1]
  end
  def login
    post sign_in_path, params: {mobile: @phone}
    post verify_sign_in_path, params: {code: code(@phone)}
  end
  def verify_current
    travel 61.seconds
    post account_mobile_current_path
    post account_mobile_verify_current_path, params: {code: code(@phone)}
  end
  test 'account page requires login and groups preferences' do
    get my_account_path
    assert_redirected_to sign_in_path
    login
    get my_account_path
    assert_response :success
    assert_select 'h1', 'My Account'
    assert_select 'a[href="/my-account/mobile"]'
    assert_select 'form[action="/sms-preferences"]'
    get activity_path
    assert_select 'form[action="/sms-preferences"]', count: 0
    patch sms_preferences_path, params: {sms_consent: '0'}
    assert_redirected_to my_account_path(anchor: 'sms-preferences')
  end
  test 'mobile change requires current and new verification and retains account data' do
    login
    post account_mobile_new_code_path, params: {mobile: @new_phone}
    assert_match(/Verify your current/, flash[:alert])
    old = AccountContact.find_by!(account_id: @account.id, kind: 'mobile', revoked_at: nil)
    Integrations::SmsConsent.grant!(@account, key: 'old-consent')
    verify_current
    post account_mobile_new_code_path, params: {mobile: @new_phone}
    assert_redirected_to account_mobile_path
    assert_nil old.reload.revoked_at
    post account_mobile_confirm_path, params: {code: code(@new_phone)}
    assert_redirected_to my_account_path
    assert old.reload.revoked_at
    new_contact = AccountContact.find_by!(account_id: @account.id, kind: 'mobile', revoked_at: nil)
    assert_equal @new_phone, Journeys::Support.decrypt(new_contact.value_ciphertext)
    assert new_contact.verified_at
    refute Integrations::SmsConsent.allowed?(new_contact.lookup_hmac)
    assert_equal 5, Account.count
    assert AuditEvent.exists?(actor_id: @account.id, action: 'mobile_changed')
    post account_mobile_confirm_path, params: {code: code(@new_phone)}
    assert_match(/Verify your current/, flash[:alert])
  end
  test 'wrong and expired codes cannot replace phone' do
    pending = Journeys::MobileChange.start!(@account, @new_phone)
    old = AccountContact.find_by!(account_id: @account.id, kind: 'mobile', revoked_at: nil)
    3.times { assert_raises(Journeys::Error) { Journeys::MobileChange.confirm!(@account, old.id, pending, 'invalid') } }
    c = AuthChallenge.find(pending['challenge_id'])
    assert_equal 3, c.failed_attempts
    assert c.invalidated_at
    assert_raises(Journeys::Error) { Journeys::MobileChange.confirm!(@account, old.id, pending, code(@new_phone)) }
    assert_nil old.reload.revoked_at
  end
  test 'duplicate number and another account challenge are rejected' do
    assert_raises(Journeys::Error) { Journeys::MobileChange.start!(@account, '+15105550102') }
    pending = Journeys::MobileChange.start!(@account, @new_phone)
    other = Account.find(JourneySeeds.id(2))
    old = AccountContact.find_by!(account_id: other.id, kind: 'mobile', revoked_at: nil)
    assert_raises(Journeys::Error) { Journeys::MobileChange.confirm!(other, old.id, pending, code(@new_phone)) }
    assert_nil old.reload.revoked_at
  end
  test 'cancel leaves number unchanged' do
    login
    verify_current
    post account_mobile_new_code_path, params: {mobile: @new_phone}
    delete account_mobile_cancel_path
    post account_mobile_confirm_path, params: {code: code(@new_phone)}
    assert_match(/Verify your current/, flash[:alert])
    assert AccountContact.exists?(account_id: @account.id, lookup_hmac: Journeys::Support.digest(@phone), revoked_at: nil)
  end
end
