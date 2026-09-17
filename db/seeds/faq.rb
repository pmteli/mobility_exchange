# Publish the approved FAQ page only: bin/rails runner db/seeds/faq.rb
Workflow.run do
  actor = User.joins(:user_roles).where(user_roles: {role_id: "admin"}, account_status: "active").first!
  Workflow.authorize!(actor, "content.manage")
  page = ContentPage.find_or_initialize_by(slug: "faq")
  body = <<~TEXT
    **Question: How do I get involved in this effort?**

    Answer: Mobility Exchange relies on the generosity of local individuals, corporate sponsors, and community volunteers to fulfill its mission:

    - **For Donors:** Donate gently used mobility devices or contribute financially to help acquire high-demand, new medical supplies.
    - **For Healthcare & Community Partners:** Refer clients in need or host equipment drive drop-off locations.
    - **For Volunteers:** Lend your time and expertise—from equipment inspection, minor refurbishments, and sanitization to inventory tracking and community outreach.
  TEXT
  page.update!(title: "Frequently asked questions", body_markdown: body, published_at: Time.current, updated_by: actor.id)
  Audit.record!(actor, "content.updated", page)
end
puts "Published /pages/faq."
