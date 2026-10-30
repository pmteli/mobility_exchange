class PhotoScreening < ApplicationRecord
  self.table_name = "freedme.photo_screenings"
  belongs_to :account
end
