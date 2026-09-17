# Publish the approved About page only: bin/rails runner db/seeds/about.rb
Workflow.run do
  actor = User.joins(:user_roles).where(user_roles: {role_id: "admin"}, account_status: "active").first!
  Workflow.authorize!(actor, "content.manage")
  page = ContentPage.find_or_initialize_by(slug: "about")
  page.update!(title: "About Mobility Exchange", body_markdown: "Mobility Exchange is a dedicated non-profit initiative to improve independence, dignity, and quality of life for underserved individuals in the Bay Area. By collecting, inspecting, sanitizing, and redistributing new and gently used Home Medical Equipment and Supplies (HMEs), Mobility Exchange bridges the gap between surplus resources and community members in need of vital mobility support.", published_at: Time.current, updated_by: actor.id)
  Audit.record!(actor, "content.updated", page)
end
puts "Published /pages/about."
