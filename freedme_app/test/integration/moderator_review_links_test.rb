require 'test_helper'
require Rails.root.join('db/seeds/journeys')
class ModeratorReviewLinksTest < ActionDispatch::IntegrationTest
  setup do
    load Rails.root.join('db/seeds.rb')
    JourneySeeds.load!
  end
  test 'review links require staff sign in and preserve destination' do
    listing = Listing.first
    get moderator_listing_review_path(listing)
    assert_redirected_to staff_sign_in_path
    assert_equal moderator_listing_review_path(listing), session[:return_to]
  end
  test 'moderator lands on the related review after sign in' do
    listing = Listing.first
    listing.update!(status: 'pending_review')
    get moderator_listing_review_path(listing)
    login_staff_account(Account.find(JourneySeeds.id(5)))
    follow_redirect!
    assert_redirected_to activity_path(review: listing.id, anchor: 'panel-review')
    follow_redirect!
    assert_response :success
  end

  test 'moderator can approve and reject listings without optional review notes' do
    login_staff_account(Account.find(JourneySeeds.id(5)))
    get activity_path
    assert_select 'textarea[id^="review_"][name="reason"][required]', count: 0
    assert_select 'label', text: 'Review notes (optional)'
    assert_select 'button', text: 'Approve & Publish'
    refute_includes response.body, 'Approve & publish (simulation)'
    %w[approve reject].each do |decision|
      listing = Listing.where(status: 'pending_review').first!
      post review_listing_path(listing), params: {decision: decision, reason: ''}
      assert_response :redirect
      assert_equal(decision == 'approve' ? 'available' : 'rejected', listing.reload.status)
    end
  end

end
