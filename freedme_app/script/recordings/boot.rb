require 'uri'
abort 'Recording mode only' unless ENV['FREEDME_RECORDING_MODE'] == 'true'
url = URI(ENV.fetch('DATABASE_URL'))
url.path = '/freedme_recording_demo'
ENV['DATABASE_URL'] = url.to_s
require 'pg'
admin_url = url.dup
admin_url.path = '/postgres'
connection = PG.connect(admin_url.to_s)
unless connection.exec_params('SELECT 1 FROM pg_database WHERE datname=$1', ['freedme_recording_demo']).ntuples > 0
  connection.exec('CREATE DATABASE freedme_recording_demo')
end
connection.close
abort 'Database preparation failed' unless system('bin/rails', 'db:prepare', 'db:seed')
abort 'Fixtures failed' unless system('bin/rails', 'runner', 'require Rails.root.join("db/seeds/journeys"); JourneySeeds.load!')
exec('bin/rails', 'server', '-b', '0.0.0.0', '-p', '3000')
