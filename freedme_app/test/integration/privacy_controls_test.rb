require 'test_helper'
require Rails.root.join('db/seeds/journeys')
class PrivacyControlsTest < ActionDispatch::IntegrationTest
  setup do
    load Rails.root.join('db/seeds.rb')
    JourneySeeds.load!
  end
  def with_backup_method(name, replacement)
    original = Privacy::ManagedBackup.method(name)
    Privacy::ManagedBackup.define_singleton_method(name) { replacement.respond_to?(:call) ? replacement.call : replacement }
    yield
  ensure
    Privacy::ManagedBackup.define_singleton_method(name, original)
  end
  def login(n)
    return login_staff_account(Account.find(JourneySeeds.id(n))) if Staff::Authentication.staff?(Account.find(JourneySeeds.id(n)))
    post sign_in_path, params: {mobile: "+1510555010#{n}"}
    code = SimulatedSmsMessage.where(recipient: "+1510555010#{n}", template_code: 'sign_in_otp').order(created_at: :desc).first!.body[/code: (\d+)/, 1]
    post verify_sign_in_path, params: {code: code}
  end
  test 'only the authenticated account can request deletion and requests are idempotent' do
    post privacy_deletion_path, params: {confirmed: '1'}
    assert_redirected_to sign_in_path
    login(3)
    post privacy_deletion_path, params: {confirmed: '1', account_id: JourneySeeds.id(1)}
    post privacy_deletion_path, params: {confirmed: '1'}
    assert_equal 1, PrivacyDeletionRequest.where(account_id: JourneySeeds.id(3)).count
    refute PrivacyDeletionRequest.exists?(account_id: JourneySeeds.id(1))
    assert_equal 'active', Account.find(JourneySeeds.id(3)).status
    get privacy_controls_path
    assert_includes response.body, 'Your data has not yet been deleted.'
    get privacy_review_path
    assert_response :forbidden
  end
  test 'moderators cannot access administrator deletion controls' do
    login(5)
    get privacy_review_path
    assert_response :forbidden
  end
  test 'backup controls require administrator and return success or safe failure' do
    post privacy_backup_path
    assert_redirected_to sign_in_path
    login(5)
    post privacy_backup_path
    assert_response :forbidden
    get activity_path
    assert_select '#backup-recovery', count: 0
    AccountRole.create!(account_id: JourneySeeds.id(5), role: 'administrator')
    with_backup_method(:status, {available: true, count: 2, latest_at: Time.current}) do
      get activity_path
      assert_response :success
      assert_select '#backup-recovery'
      assert_select 'form[action=?]', privacy_backup_path
    end
    called = false
    with_backup_method(:create!, -> { called = true }) do
      post privacy_backup_path
      assert_redirected_to activity_path(anchor: 'backup-recovery')
      assert_includes flash[:notice], 'created successfully'
    end
    assert called
    with_backup_method(:create!, -> { raise Privacy::ManagedBackup::Error, 'private diagnostic' }) do
      post privacy_backup_path
      assert_redirected_to activity_path(anchor: 'backup-recovery')
      assert_includes flash[:alert], 'could not be created'
      refute_includes flash[:alert], 'private diagnostic'
    end
  end

  test 'operations documentation is available only to administrators' do
    get privacy_operations_path
    assert_redirected_to sign_in_path
    login(5)
    get privacy_operations_path
    assert_response :forbidden
    AccountRole.create!(account_id: JourneySeeds.id(5), role: 'administrator')
    get privacy_review_path
    assert_select 'a[href=?]', privacy_operations_path
    get privacy_operations_path
    assert_response :success
    assert_includes response.body, 'FreeDME privacy operations'
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_includes response.body, ERB::Util.html_escape(File.read(Rails.root.join('docs/PRIVACY_OPERATIONS.txt')))
  end

  test 'administrator reviews quarterly inactive accounts without deleting them' do
    AccountRole.create!(account_id: JourneySeeds.id(5), role: 'administrator')
    inactive = Account.find(JourneySeeds.id(1))
    inactive.update!(last_activity_at: 4.months.ago)
    login(5)
    get privacy_review_path
    assert_response :success
    assert_includes response.body, inactive.display_name
    patch privacy_review_account_path(inactive)
    assert inactive.reload.last_inactivity_reviewed_at
    assert_equal 'active', inactive.status
    get privacy_review_path
    refute_includes response.body, inactive.display_name
  end
end
