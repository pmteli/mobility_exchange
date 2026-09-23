Rails.application.config.session_store :cookie_store, key: "_mobility_exchange", secure: Rails.env.production?, httponly: true, same_site: :lax
Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.script_src :self
  policy.style_src :self
  policy.img_src :self, :data
  policy.font_src :self
  policy.object_src :none
  policy.base_uri :self
  policy.form_action :self, "https://checkout.stripe.com", "https://accounts.google.com"
  policy.frame_ancestors :none
end
