# Explicit, isolated recording process only. Never enabled in the regular app.
if ENV['FREEDME_RECORDING_MODE'] == 'true'
  require 'uri'
  abort 'Recording mode is development-only' unless Rails.env.development?
  url = URI(ENV.fetch('DATABASE_URL'))
  url.path = '/freedme_recording_demo'
  ENV['DATABASE_URL'] = url.to_s
  Aws.config[:rekognition] = {stub_responses: true}
  fields = {'FIRST_NAME'=>'Maya', 'LAST_NAME'=>'Example', 'ADDRESS'=>'100 Example Lane', 'CITY_IN_ADDRESS'=>'Fremont', 'STATE_IN_ADDRESS'=>'CA', 'ZIP_CODE_IN_ADDRESS'=>'94536'}
  Aws.config[:textract] = {stub_responses: {
    analyze_id: {identity_documents: [{identity_document_fields: fields.map { |key,value| {type:{text:key},value_detection:{text:value}} }}]},
    analyze_document: {blocks: []}
  }}
end

# Deterministic, harmless non-equipment rejection for the recorded photo journey.
# Only this fixture digest is affected, and only in the isolated development demo.
if ENV['FREEDME_RECORDING_MODE'] == 'true'
  module RecordingPhotoFixture
    def check(path, account)
      if ApplicationRecord.connection.select_value('SELECT current_database()') == 'freedme_recording_demo' &&
          Digest::SHA256.file(path).hexdigest == 'f0e546bed2404a70b9d3b4dd955cd47c7ecbeaa10659519251da66c7d4d28470'
        return {state: 'rejected', message: 'This simulated screening result rejects a non-equipment image. Remove it and upload an equipment photo.'}
      end
      super
    end
  end
  Rails.application.config.to_prepare do
    EquipmentMedia::Moderation.singleton_class.prepend(RecordingPhotoFixture) unless EquipmentMedia::Moderation.singleton_class.ancestors.include?(RecordingPhotoFixture)
  end
end
