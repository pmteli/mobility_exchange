class PagesController < ApplicationController
  def privacy
    render file: Rails.root.join("public/coming-soon/privacy.html"), layout: false
  end

  def sms_terms
    render file: Rails.root.join("public/coming-soon/sms-terms.html"), layout: false
  end

  def sms_consent
    render file: Rails.root.join("public/coming-soon/sms-consent.html"), layout: false
  end

  def home; end
  def decisions; end
  def how; end
  def resources; end
  def team; end
end
