class AccountMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAIL_FROM", "no-reply@example.test") }
  def notification(record)
    @kind = record.template_key
    if %w[welcome_donor welcome_volunteer].include?(@kind)
      @donor = @kind == "welcome_donor"
      @first_name = record.payload_json.fetch("first_name", "there")
      @heading = @donor ? "Thank you for giving mobility a new chapter." : "Thank you for stepping forward."
      @intro = @donor ? "Welcome to Mobility Exchange! Thank you for registering as a donor and helping build a community where more people can move with independence and dignity." : "Welcome to Mobility Exchange! Thank you for offering your time and talents to support individuals and families across the Bay Area."
      @body = @donor ? "Your willingness to share new or gently used mobility equipment can help connect surplus resources with people who need support. When you're ready, tell us about your equipment and add photos if you have them. Our team will review your submission and guide you through the next steps." : "Volunteers make this effort possible—from equipment inspection, minor refurbishments, and sanitization to inventory tracking and community outreach. Every contribution helps equipment find its next home."
      @next_step = @donor ? "Start by submitting an equipment donation. Please wait for our team's review before arranging a drop-off." : "Complete your volunteer application so our team can learn how you'd like to help. Volunteer approval is required before you can sign up for a shift."
      @target = @donor ? new_donation_url : new_volunteer_application_url
      @button = @donor ? "Start a donation" : "Complete volunteer application"
      return mail(to: record.destination, subject: @donor ? "Welcome, and thank you for joining as a donor" : "Welcome, and thank you for volunteering", template_name: "welcome")
    end
    @token = record.payload_json.fetch("token")
    raise ArgumentError, "Unsupported mail template" unless %w[verification reset email_change].include?(@kind)
    mail(to: record.destination, subject: @kind == "reset" ? "Reset your Mobility Exchange password" : "Verify your Mobility Exchange email")
  end
end
