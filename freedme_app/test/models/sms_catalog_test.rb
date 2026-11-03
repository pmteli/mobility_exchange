require "test_helper"

class SmsCatalogTest < ActiveSupport::TestCase
  test "every SMS template renders its named variables" do
    catalog = I18n.t!("sms", locale: :en)
    assert_equal 19, catalog.size
    catalog.each do |key, text|
      parameters = text.scan(/%\{([a-z_]+)\}/).flatten.to_h { |name| [name.to_sym, "Sample #{name}"] }
      message = Integrations::SmsGateway.new.deliver(to: "+15105550199", template: key, parameters: parameters)
      refute_match(/%\{/, message.body)
      parameters.except(:link).each_value { |value| assert_includes message.body, value }
      assert_includes message.body, Integrations::SmsLinks.url(key)
      assert Integrations::SmsLinks::DESTINATIONS.key?(Integrations::SmsLinks::TEMPLATE_CODES.fetch(key.to_s))
    end
  end

  test "missing variables fail without recording a message" do
    assert_no_difference "SimulatedSmsMessage.count" do
      assert_raises(I18n::MissingInterpolationArgument) do
        Integrations::SmsGateway.new.deliver(to: "+15105550199", template: "listing_submitted", parameters: {})
      end
    end
  end

  test "values are interpolated once and repeated delivery is deduplicated" do
    args = {to: "+15105550199", template: "listing_submitted", parameters: {item_title: "Walker %{display_name}"}, idempotency_key: "catalog-test"}
    assert_difference "SimulatedSmsMessage.count", 1 do
      2.times { Integrations::SmsGateway.new.deliver(**args) }
    end
    assert_includes SimulatedSmsMessage.find_by!(idempotency_key: "catalog-test").body, "Walker %{display_name}"
  end
end
