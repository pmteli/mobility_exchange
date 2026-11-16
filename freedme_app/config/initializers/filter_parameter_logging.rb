Rails.application.config.filter_parameters += %i[password code otp token secret authorization phone mobile email address first_name last_name document evidence ciphertext lookup_hmac question answer]

Rails.application.config.filter_parameters += %i[location locality notes display_name]

Rails.application.config.filter_parameters += [:photo, :photos]

Rails.application.config.filter_parameters += %i[identity_document fields home_address zip_code]

Rails.application.config.filter_parameters += %i[From To Body recipient_hmac]
Rails.application.config.filter_parameters += [:privacy_backup_key]
Rails.application.config.filter_parameters += %i[identifier staff_pending staff_auth_version]
