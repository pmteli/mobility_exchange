require "test_helper"
class TestEquipmentSeedsTest < ActiveSupport::TestCase
  test "25 illustrated sample items are available and repeat runs preserve inventory" do
    load Rails.root.join("db/seeds/test_equipment.rb")
    items = Equipment.where("equipment.id LIKE ?", "sample-equipment-%")
    assert_equal 25, items.count
    assert_equal 25, items.visible.count
    assert_equal({"wheelchairs" => 6, "walkers" => 7, "bath" => 5, "walking_aids" => 7}, items.joins(:equipment_type).group("equipment_types.category_id").count)
    before = items.pluck(:id, :updated_at).sort
    load Rails.root.join("db/seeds/test_equipment.rb")
    assert_equal before, items.pluck(:id, :updated_at).sort
    %w[wheelchair walker rollator shower-chair cane crutches].each do |kind|
      assert File.exist?(Rails.root.join("public/design/#{kind}.svg"))
    end
  end
end
