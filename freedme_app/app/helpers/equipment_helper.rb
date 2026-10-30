module EquipmentHelper
  def offer_label(item)
    item.offer_kind == "loan" ? "FREE LOAN: UNTIL #{item.loan_until.strftime('%b %-d, %Y')}" : "FREE TO KEEP"
  end
end
