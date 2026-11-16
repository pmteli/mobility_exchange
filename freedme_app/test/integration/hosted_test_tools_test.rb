require 'test_helper'
require Rails.root.join('db/seeds/journeys')
class HostedTestToolsTest < ActionDispatch::IntegrationTest
  setup do
    load Rails.root.join('db/seeds.rb')
    JourneySeeds.load!
    @old_hosted = Rails.configuration.x.hosted_demo
    Rails.configuration.x.hosted_demo = true
  end
  teardown { Rails.configuration.x.hosted_demo = @old_hosted }
  def login(n)
    return login_staff_account(Account.find(JourneySeeds.id(n))) if Staff::Authentication.staff?(Account.find(JourneySeeds.id(n)))
    post sign_in_path, params: {mobile: "+1510555010#{n}"}
    m = SimulatedSmsMessage.where(recipient: "+1510555010#{n}", template_code: 'sign_in_otp').order(created_at: :desc).first!
    post verify_sign_in_path, params: {code: m.body[/code: (\d+)/, 1]}
  end
  test 'hosted tools require administrator and are absent from normal navigation' do
    get test_data_path
    assert_redirected_to sign_in_path
    login(3)
    get test_data_path
    assert_response :forbidden
    get activity_path
    assert_select 'a[href="/test-data"]', count: 0
    assert_includes response.body, 'Private prelaunch testing'
    refute_includes response.body, 'Use fictional test data and documents only.'
    login(5)
    get test_data_path
    assert_response :forbidden
    AccountRole.create!(account_id: JourneySeeds.id(5), role: 'administrator')
    get test_data_path
    assert_response :success
    get activity_path
    assert_select 'a[href="/test-data"]', text: 'Test data tools'
  end
  test 'local simulated testing retains tools access' do
    Rails.configuration.x.hosted_demo = false
    get test_data_path
    assert_response :success
  end
end
