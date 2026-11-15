# FR003/FR018 and NFR003: explicit isolated review deployment, not live service.
Rails.configuration.x.hosted_demo = ENV["FREEDME_HOSTED_DEMO"] == "true"
if Rails.configuration.x.hosted_demo
  require "uri"
  abort "Hosted demo requires its own database" unless URI(ENV.fetch("DATABASE_URL")).path == "/freedme_hosted_demo"
  Rails.application.config.hosts = ["demo.freedme.org", "www.freedme.org", "localhost", "127.0.0.1"]
  Rails.application.config.action_dispatch.cookies_same_site_protection = :lax
end
