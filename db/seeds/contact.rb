# Publish the approved Contact page only: bin/rails runner db/seeds/contact.rb
Workflow.run do
  actor = User.joins(:user_roles).where(user_roles: {role_id: "admin"}, account_status: "active").first!
  Workflow.authorize!(actor, "content.manage")
  page = ContentPage.find_or_initialize_by(slug: "contact")
  body = <<~TEXT
    To learn more about you can get involved in this initiative, please contact us:

    **Email:** inquiry@mobilityexchange.org

    **Phone:** 1-888-88-8888

    **Facebook:** facebook.com/mobility-exchange
  TEXT
  page.update!(title: "Contact us", body_markdown: body, published_at: Time.current, updated_by: actor.id)
  Audit.record!(actor, "content.updated", page)
end
puts "Published /pages/contact."
