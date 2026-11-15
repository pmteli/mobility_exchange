require 'open3'
require 'fileutils'

module Privacy
  # Encrypted logical database backups. Original uploaded identity images are never
  # included, so restoring one cannot reintroduce an expired source document.
  # Equipment-photo storage and infrastructure snapshots need separate controls.
  class ManagedBackup
    class Error < StandardError; end
    def self.directory
      value = ENV.fetch('PRIVACY_BACKUP_DIRECTORY') { raise Error, 'Configure a private persistent backup directory.' }
      path = Pathname.new(value).expand_path
      raise Error, 'Backups must be outside public and source directories.' if path.to_s.start_with?(Rails.root.to_s + '/')
      FileUtils.mkdir_p(path, mode: 0700)
      raise Error, 'Backup directory must not be a symlink.' unless path.realpath == path
      File.chmod(0700, path)
      path
    end

    def self.encryptor
      hex = ENV['PRIVACY_BACKUP_KEY'].to_s
      raise Error, 'Configure an independent 64-character hexadecimal backup encryption key.' unless hex.match?(/\A[0-9a-fA-F]{64}\z/)
      ActiveSupport::MessageEncryptor.new([hex].pack('H*'), cipher: 'aes-256-gcm', serializer: :json)
    end

    def self.status
      encryptor
      files = directory.glob('*.backup').reject(&:symlink?).select(&:file?)
      {available: true, count: files.size, latest_at: files.map(&:mtime).max}
    rescue Error, SystemCallError
      {available: false, count: 0, latest_at: nil}
    end

    def self.run_due!
      return if ENV['PRIVACY_BACKUP_DIRECTORY'].blank?
      latest = directory.glob('*.backup').map(&:mtime).max
      create! unless latest && latest > 24.hours.ago
    end

    def self.create!
      cipher = encryptor
      root = directory
      File.open(root.join('.lock'), File::RDWR | File::CREAT, 0600) do |lock|
        lock.flock(File::LOCK_EX)
        sql = database_dump
        envelope = {format: 1, created_at: Time.current.iso8601,
          identity_images_included: false, database_sql: sql}
        path = root.join("#{Time.current.utc.strftime('%Y%m%dT%H%M%S')}-#{SecureRandom.uuid}.backup")
        temporary = Pathname.new("#{path}.partial")
        begin
          File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0600) do |file|
            file.write(cipher.encrypt_and_sign(envelope))
            file.flush
            file.fsync
          end
          File.rename(temporary, path)
        ensure
          FileUtils.rm_f(temporary)
        end
        path
      end
    end

    # Restores only into an explicitly named, already-created EMPTY scratch DB.
    # Production cutover remains a separately reviewed operation.
    def self.restore_into!(basename:, database:)
      unless basename.to_s.match?(/\A[0-9T-]+-[0-9a-f-]{36}\.backup\z/) && database.to_s.match?(/\Afreedme_restore_[a-z0-9_]+\z/)
        raise Error, 'Use a generated backup name and a freedme_restore_ scratch database.'
      end
      path = directory.join(basename)
      raise Error, 'Backup may not be a symlink.' if path.symlink?
      envelope = encryptor.decrypt_and_verify(File.binread(path))
      raise Error, 'Unsupported backup format.' unless envelope['format'] == 1 && envelope['identity_images_included'] == false
      env = database_environment.merge('PGDATABASE' => database)
      output, _, status = Open3.capture3(env, 'psql', '-X', '-tAc',
        "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname NOT IN ('pg_catalog','information_schema') AND n.nspname NOT LIKE 'pg_toast%' AND c.relkind IN ('r','p','v','m','S')")
      raise Error, 'Restore requires an empty scratch database.' unless status.success? && output.strip == '0'
      _, _, status = Open3.capture3(env, 'psql', '-X', '--set=ON_ERROR_STOP=1', '--single-transaction', stdin_data: envelope.fetch('database_sql'))
      raise Error, 'Scratch restore failed and was rolled back.' unless status.success?
      true
    end

    def self.database_environment
      config = ApplicationRecord.connection_db_config.configuration_hash
      {'PGHOST' => config[:host].to_s, 'PGPORT' => (config[:port] || 5432).to_s,
        'PGUSER' => config[:username].to_s, 'PGPASSWORD' => config[:password].to_s,
        'PGDATABASE' => config[:database].to_s, 'PGCONNECT_TIMEOUT' => '10'}
    end

    def self.database_dump
      connection = ApplicationRecord.connection
      env = database_environment
      connection.transaction(isolation: :repeatable_read) do
        snapshot = connection.select_value('SELECT pg_export_snapshot()')
        dump, _, status = Open3.capture3(env, 'pg_dump', '--no-owner',
          '--exclude-table-data=freedme.identity_document_uploads', "--snapshot=#{snapshot}")
        raise Error, 'Database backup failed. Check database connectivity and pg_dump version without logging credentials.' unless status.success?
        columns = IdentityDocumentUpload.column_names.map { |name| connection.quote_column_name(name) }
        projection = columns.map do |name|
          case name
          when '"image_ciphertext"' then 'NULL::bytea AS image_ciphertext'
          when '"image_deleted_at"' then 'COALESCE(image_deleted_at, CURRENT_TIMESTAMP) AS image_deleted_at'
          else name
          end
        end
        dump << "\nCOPY freedme.identity_document_uploads (#{columns.join(', ')}) FROM stdin;\n"
        connection.raw_connection.copy_data("COPY (SELECT #{projection.join(', ')} FROM freedme.identity_document_uploads) TO STDOUT") do
          while (row = connection.raw_connection.get_copy_data)
            dump << row
          end
        end
        dump << "\\.\n"
        dump
      end
    end
  end
end
