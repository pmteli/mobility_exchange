require 'test_helper'
require Rails.root.join('db/seeds/journeys')
class StaffAuthenticationTest < ActionDispatch::IntegrationTest
  setup do
    load Rails.root.join('db/seeds.rb')
    JourneySeeds.load!
    @password = 'A unique test staff passphrase!'
    @credential = Staff::Provisioner.create!(email: 'staff@example.test', username: 'reviewer', password: @password, first_name: 'Test', last_name: 'Moderator', role: 'moderator')
  end
  def password_step(identifier = 'reviewer')
    post staff_sign_in_path, params: {identifier: identifier, password: @password}
    assert_redirected_to staff_verify_path
  end
  def finish
    post staff_verify_path, params: {code: Staff::Authentication.totp(@credential).now}
  end
  test 'password alone grants no access; first authenticator enrollment grants staff access' do
    password_step('STAFF@example.test')
    get activity_path
    assert_redirected_to sign_in_path
    get staff_verify_path
    assert_response :success
    assert_includes response.body, 'Set up your authenticator'
    assert_select '.staff-enrollment-qr svg[role="img"]', count: 1
    assert_select 'details code', text: Journeys::Support.decrypt(@credential.mfa_secret_ciphertext)
    assert_equal 'no-store', response.headers['Cache-Control']
    finish
    assert_redirected_to activity_path
    assert @credential.reload.mfa_enrolled_at
    get activity_path
    assert_response :success
    assert_includes response.body, 'Listing Reviews'
    get my_account_path
    assert_response :success
    refute_includes response.body, 'Change mobile number'
    post account_mobile_current_path
    assert_redirected_to my_account_path
    get privacy_review_path
    assert_response :forbidden
  end
  test 'MFA fails closed, expires, and rejects replay' do
    get staff_verify_path
    assert_redirected_to staff_sign_in_path
    post staff_verify_path, params: {code: '000000'}
    assert_redirected_to staff_sign_in_path
    password_step
    travel 6.minutes
    finish
    assert_redirected_to staff_sign_in_path
    password_step
    code = Staff::Authentication.totp(@credential).now
    post staff_verify_path, params: {code: code}
    assert_redirected_to activity_path
    delete sign_out_path
    password_step
    get staff_verify_path
    assert_select '.staff-enrollment-qr', count: 0
    refute_includes response.body, Journeys::Support.decrypt(@credential.mfa_secret_ciphertext)
    post staff_verify_path, params: {code: code}
    assert_response :unprocessable_entity
    get activity_path
    assert_redirected_to sign_in_path
  end
  test 'bad passwords lock the account and new password requests do not reset MFA failures' do
    5.times do
      post staff_sign_in_path, params: {identifier: 'reviewer', password: 'wrong'}
      assert_response :unprocessable_entity
    end
    assert @credential.reload.locked_until > Time.current
    post staff_sign_in_path, params: {identifier: 'reviewer', password: @password}
    assert_response :unprocessable_entity
    travel 16.minutes
    password_step
    post staff_verify_path, params: {code: 'invalid'}
    assert_response :unprocessable_entity
    assert_select '.staff-enrollment-qr svg', count: 1
    assert_equal 'no-store', response.headers['Cache-Control']
    assert_equal 1, @credential.reload.failed_attempts
    password_step
    assert_equal 1, @credential.reload.failed_attempts
  end
  test 'operator recovery revokes existing staff session and requires reenrollment' do
    password_step
    finish
    old_version = @credential.session_version
    Staff::Provisioner.reset!('reviewer', 'A replacement long passphrase!')
    assert_not_equal old_version, @credential.reload.session_version
    assert_nil @credential.mfa_enrolled_at
    get activity_path
    assert_redirected_to sign_in_path
  end
  test 'staff cannot authenticate using member SMS flow including previously issued challenges' do
    member = Account.find(JourneySeeds.id(1))
    pending = Journeys::Authentication.start!(mobile: '5105550101')
    message = SimulatedSmsMessage.where(recipient: '+15105550101', template_code: 'sign_in_otp').order(created_at: :desc).first!
    AccountRole.create!(account_id: member.id, role: 'moderator')
    assert_raises(Journeys::Error) { Journeys::Authentication.verify!(pending, message.body[/code: (\d+)/,1]) }
    post sign_in_path, params: {mobile: '5105550101'}
    assert_response :unprocessable_entity
    assert_includes response.body, 'Staff Sign In'
  end
  test 'eight character passwords work for creation and reset but seven characters fail' do
    options = {email: 'boundary@example.test', username: 'boundary', first_name: 'Test', last_name: 'Staff', role: 'moderator'}
    assert_raises(ArgumentError) { Staff::Provisioner.create!(**options, password: 'Abcd123') }
    credential = Staff::Provisioner.create!(**options, password: 'Abcd1234')
    assert credential.authenticate('Abcd1234')
    credential.password = 'Abcd123'
    refute credential.valid?
    assert_raises(ArgumentError) { Staff::Provisioner.reset!('boundary', 'Abcd123') }
    credential = Staff::Provisioner.reset!('boundary', 'Efgh5678')
    assert credential.authenticate('Efgh5678')
  end

  test 'provisioning validates roles, passwords and duplicate usernames without orphan accounts' do
    options = {email: 'other@example.test', username: 'reviewer', password: @password, first_name: 'Other', last_name: 'Staff', role: 'moderator'}
    assert_no_difference 'Account.count' do
      assert_raises(ActiveRecord::RecordInvalid) { Staff::Provisioner.create!(**options) }
      assert_raises(ArgumentError) { Staff::Provisioner.create!(**options.merge(role: 'superuser')) }
      assert_raises(ArgumentError) { Staff::Provisioner.create!(**options.merge(password: 'short')) }
    end
    admin = Staff::Provisioner.create!(**options.merge(username: 'administrator', role: 'administrator'))
    assert AccountRole.exists?(account_id: admin.account_id, role: 'administrator')
    assert AccountRole.exists?(account_id: admin.account_id, role: 'moderator')
  end
end
