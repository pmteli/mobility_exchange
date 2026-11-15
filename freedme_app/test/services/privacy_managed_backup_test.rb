require 'test_helper'
require 'tmpdir'
require Rails.root.join('db/seeds/journeys')

class PrivacyManagedBackupTest < ActiveSupport::TestCase
  self.use_transactional_tests = false
  setup do
    @previous = ENV.to_h.slice('PRIVACY_BACKUP_DIRECTORY', 'PRIVACY_BACKUP_KEY')
    @directory = Dir.mktmpdir('privacy-backup-test-')
    ENV['PRIVACY_BACKUP_DIRECTORY'] = @directory
    ENV['PRIVACY_BACKUP_KEY'] = SecureRandom.hex(32)
    load Rails.root.join('db/seeds.rb')
    JourneySeeds.load!
  end
  teardown do
    @upload&.destroy!
    %w[PRIVACY_BACKUP_DIRECTORY PRIVACY_BACKUP_KEY].each { |key| ENV.delete(key) }
    @previous.each { |key, value| ENV[key] = value }
    FileUtils.remove_entry(@directory)
  end

  test 'encrypted PostgreSQL backup excludes original identity image bytes' do
    listing = Listing.find(JourneySeeds.id(1000))
    @upload = IdentityDocumentUpload.create!(account_id: JourneySeeds.id(3), listing_id: listing.id,
      revision_id: listing.current_revision_id, document_kind: 'utility_bill', state: 'extracted',
      purge_due_at: 7.days.from_now, image_ciphertext: 'unique-source-document-marker',
      fields_ciphertext: IdentityDocuments::Vault.encrypt({first_name: 'Private test name'}.to_json))
    path = Privacy::ManagedBackup.create!
    encoded = File.binread(path)
    refute_includes encoded, 'CREATE TABLE'
    envelope = Privacy::ManagedBackup.encryptor.decrypt_and_verify(encoded)
    assert_equal false, envelope['identity_images_included']
    sql = envelope['database_sql']
    assert_includes sql, 'CREATE TABLE freedme.accounts'
    assert_includes sql, 'COPY freedme.identity_document_uploads'
    refute_includes sql, 'unique-source-document-marker'
    refute_includes sql, 'unique-source-document-marker'.unpack1('H*')
    assert_includes sql, @upload.id
    assert_equal 0600, File.stat(path).mode & 0777
    # Provision this empty scratch database separately with an owner credential.
    # The application runtime deliberately does not have CREATEDB privilege.
    name = ENV['PRIVACY_RESTORE_TEST_DATABASE']
    return if name.blank?
    begin
      assert Privacy::ManagedBackup.restore_into!(basename: path.basename.to_s, database: name)
      config = ApplicationRecord.connection_db_config.configuration_hash
      restored = PG.connect(host: config[:host], port: config[:port], user: config[:username], password: config[:password], dbname: name)
      begin
        row = restored.exec_params('SELECT image_ciphertext, image_deleted_at, fields_ciphertext FROM freedme.identity_document_uploads WHERE id=$1', [@upload.id]).first
        assert_nil row['image_ciphertext']
        assert row['image_deleted_at']
        assert row['fields_ciphertext']
        assert_equal '0', restored.exec("SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a WHERE n.nspname='freedme' AND a.grantee=0 AND a.privilege_type='EXECUTE'").first['count']
      ensure
        restored.close
      end
      assert_raises(Privacy::ManagedBackup::Error) { Privacy::ManagedBackup.restore_into!(basename: path.basename.to_s, database: name) }
    end
  end

  test 'backup fails closed without an independent encryption key' do
    ENV.delete('PRIVACY_BACKUP_KEY')
    assert_raises(Privacy::ManagedBackup::Error) { Privacy::ManagedBackup.create! }
    assert_empty Dir.glob(File.join(@directory, '*.backup'))
  end
end
