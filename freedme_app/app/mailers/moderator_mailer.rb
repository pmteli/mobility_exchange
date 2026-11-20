class ModeratorMailer < ActionMailer::Base
  def listing_review(email:, review_url:)
    mail(to: email, from: ENV.fetch("MODERATOR_EMAIL_FROM", "FreeDME <info@mobilityexchange.org>"),
      subject: I18n.t!("moderator_email.listing_review_subject"),
      body: I18n.t!("moderator_email.listing_review_body", link: review_url), content_type: "text/plain")
  end
end
