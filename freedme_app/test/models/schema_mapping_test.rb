require "test_helper"

class SchemaMappingTest < ActiveSupport::TestCase
  test "every schema table has an explicit model and matching primary key" do
    Rails.application.eager_load!
    connection = ApplicationRecord.connection
    tables = connection.select_values("SELECT tablename FROM pg_tables WHERE schemaname = 'freedme'")
    assert_equal 56, tables.size
    tables.each do |table|
      model = table.classify.constantize
      assert_equal "freedme.#{table}", model.table_name
      assert_equal connection.primary_keys(model.table_name), Array(model.primary_key)
      assert model.columns.any?
      model.reflect_on_all_associations.each do |association|
        assert association.klass < ApplicationRecord
        owner = association.macro == :belongs_to ? model : association.klass
        Array(association.foreign_key).each { |key| assert_includes owner.column_names, key.to_s }
      end
    end
  end

  test "public projection is read only and excludes private identity" do
    assert AvailableListingCard.new.readonly?
    %w[value_ciphertext first_name_ciphertext address_ciphertext mobile].each do |column|
      refute_includes AvailableListingCard.column_names, column
    end
    assert_raises(ActiveRecord::ReadOnlyRecord) { AvailableListingCard.new.save! }
  end

  test "unconfigured integrations cannot send or verify" do
    assert_raises(I18n::MissingTranslationData) { Integrations::SmsGateway.new.deliver(to: "sample", template: "unknown_template", parameters: {}) }
    assert_raises(Integrations::NotConfigured) { Integrations::IdentityVerifier.new.verify(evidence_id: "sample") }
    assert_raises(Integrations::NotConfigured) { Integrations::OtpVerifier.new.verify(challenge_id: "sample", code: "123456") }
  end
  test "restored functions are not executable by PUBLIC" do
    count = ApplicationRecord.connection.select_value(<<~SQL)
      SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
      WHERE n.nspname='freedme' AND a.grantee=0 AND a.privilege_type='EXECUTE'
    SQL
    assert_equal 0, count.to_i
  end
end
