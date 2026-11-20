module Integrations
  # Short, first-party links. Never place identity details or OTPs in URLs.
  module SmsLinks
    DESTINATIONS = {
      "review" => "/activity#panel-review", "home" => "/", "find" => "/equipment", "items" => "/activity#panel-inventory",
      "requests" => "/activity#panel-requests", "qa" => "/activity#panel-questions",
      "login" => "/sign-in/verify"
    }.freeze
    TEMPLATE_CODES = {
      "moderator_listing_review" => "review", "registration_welcome" => "home", "sign_in_otp" => "login",
      "listing_submitted" => "items", "listing_published" => "items", "listing_rejected" => "items",
      "request_declined" => "find", "item_unavailable" => "find",
      "question_received" => "qa", "question_answered" => "qa",
      "pickup_followup" => "requests", "request_received" => "requests", "donor_approval_ack" => "requests",
      "request_approved" => "requests", "handoff_proposed" => "requests",
      "handoff_accepted" => "requests", "handoff_confirmed" => "requests",
      "return_confirmed" => "requests", "request_cancelled" => "requests", "request_expired" => "requests"
    }.freeze
    def self.url(template)
      default_origin = if Rails.env.production?
        "https://freedme.org"
      else
        ENV["FREEDME_RECORDING_MODE"] == "true" ? "http://127.0.0.1:3002" : "http://localhost:3001"
      end
      origin = ENV.fetch("SMS_LINK_BASE_URL", default_origin).delete_suffix("/")
      "#{origin}/s/#{TEMPLATE_CODES.fetch(template.to_s)}"
    end
  end
end
