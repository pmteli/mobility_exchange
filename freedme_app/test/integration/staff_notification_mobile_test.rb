require 'test_helper'
require Rails.root.join('db/seeds/journeys')
class StaffNotificationMobileTest < ActionDispatch::IntegrationTest
  setup do
    load Rails.root.join('db/seeds.rb')
    JourneySeeds.load!
    @staff = Staff::Provisioner.create!(email: 'new-moderator@example.test', username: 'mobile-moderator',
      password: 'Test-only staff password 2026!', first_name: 'New', last_name: 'Moderator', role: 'moderator').account
    login_staff_account(@staff)
  end
  test 'staff can verify an initial notification number without changing staff authentication or granting consent' do
    get staff_notification_mobile_path
    assert_response :success
    post staff_notification_mobile_path, params: {mobile: '5105550998'}
    assert_redirected_to staff_notification_mobile_path
    code = SimulatedSmsMessage.where(recipient: '+15105550998', template_code: 'sign_in_otp').order(created_at: :desc).first!.body[/code: (\d+)/, 1]
    post confirm_staff_notification_mobile_path, params: {code: 'wrong'}
    refute AccountContact.exists?(account_id: @staff.id, kind: 'mobile', revoked_at: nil)
    post confirm_staff_notification_mobile_path, params: {code: code}
    assert_redirected_to my_account_path(anchor: 'sms-preferences')
    contact = AccountContact.find_by!(account_id: @staff.id, kind: 'mobile', revoked_at: nil)
    assert contact.verified_at
    refute Integrations::SmsConsent.allowed?(contact.lookup_hmac)
    get my_account_path
    assert_response :success
    patch sms_preferences_path, params: {sms_consent: '1'}
    assert Integrations::SmsConsent.allowed?(contact.lookup_hmac)
    get staff_notification_mobile_path
    assert_redirected_to my_account_path
  end
  test 'staff notification number can belong to a member without sharing login or consent' do
    contact = AccountContact.where(kind: 'mobile', staff_notification: false, revoked_at: nil).first!
    phone = Journeys::Support.decrypt(contact.value_ciphertext)
    post staff_notification_mobile_path, params: {mobile: phone}
    assert_redirected_to staff_notification_mobile_path
    code = SimulatedSmsMessage.where(recipient: phone, template_code: 'sign_in_otp').order(created_at: :desc).first!.body[/code: (\d+)/, 1]
    post confirm_staff_notification_mobile_path, params: {code: code}
    assert_redirected_to my_account_path(anchor: 'sms-preferences')
    staff_contact = AccountContact.find_by!(account_id: @staff.id, kind: 'mobile', revoked_at: nil)
    assert staff_contact.staff_notification
    assert_equal contact.lookup_hmac, staff_contact.lookup_hmac
    refute Integrations::SmsConsent.allowed?(staff_contact.lookup_hmac, account_id: @staff.id)
    assert_equal contact.id, AccountContact.find_by!(kind: 'mobile', staff_notification: false, lookup_hmac: contact.lookup_hmac, revoked_at: nil).id
    Integrations::SmsConsent.grant!(@staff, key: SecureRandom.uuid)
    assert Integrations::SmsConsent.allowed?(staff_contact.lookup_hmac, account_id: @staff.id)
    ConsentEvent.create!(account_id: contact.account_id, contact_id: contact.id, purpose: 'routine_sms', action: 'stop', idempotency_key: SecureRandom.uuid)
    refute Integrations::SmsConsent.allowed?(staff_contact.lookup_hmac, account_id: @staff.id)
  end

  test 'a member can register after staff enrolls the same number and phone login selects only the member' do
    phone = '+15105550997'
    staff_contact = AccountContact.create!(account_id: @staff.id, kind: 'mobile', lookup_hmac: Journeys::Support.digest(phone), value_ciphertext: Journeys::Support.encrypt(phone), key_version: 'fictional-seed-v1', verified_at: Time.current)
    assert staff_contact.staff_notification
    assert_raises(Journeys::Authentication::RegistrationRequired) { Journeys::Authentication.start!(mobile: phone) }
    pending = Journeys::Authentication.start!(mobile: phone, registration: true, name: 'Separate Member', locality: 'Fremont')
    code = SimulatedSmsMessage.where(recipient: phone, template_code: 'sign_in_otp').order(created_at: :desc).first!.body[/code: (\d+)/, 1]
    member = Journeys::Authentication.verify!(pending, code)
    refute_equal @staff.id, member.id
    refute Staff::Authentication.staff?(member)
    travel 2.minutes do
      login = Journeys::Authentication.start!(mobile: phone)
      assert_equal member.id, AuthChallenge.find(login.fetch('challenge_id')).account_id
      assert_raises(Journeys::Error) { Journeys::Authentication.start!(mobile: phone, registration: true, name: 'Duplicate', locality: 'Fremont') }
    end
    Journeys::Support.notify(member, 'registration_welcome', {display_name: member.display_name})
    assert SimulatedSmsMessage.exists?(recipient_account_id: member.id, template_code: 'registration_welcome')
    refute SimulatedSmsMessage.exists?(recipient_account_id: @staff.id, template_code: 'registration_welcome')
  end

end
