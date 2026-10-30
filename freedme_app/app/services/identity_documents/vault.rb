module IdentityDocuments
  class Vault
    def self.encryptor
      key = Rails.application.key_generator.generate_key('freedme identity documents v1', 32)
      ActiveSupport::MessageEncryptor.new(key, cipher: 'aes-256-gcm', serializer: :json)
    end
    def self.encrypt(value)
      encryptor.encrypt_and_sign(Base64.strict_encode64(value))
    end
    def self.decrypt(value)
      Base64.strict_decode64(encryptor.decrypt_and_verify(value))
    end
    def self.purge!
      IdentityDocumentUpload.where('purge_due_at <= ?', Time.current).where(image_deleted_at: nil)
        .update_all(image_ciphertext: nil, image_deleted_at: Time.current, updated_at: Time.current)
    end
  end
end
