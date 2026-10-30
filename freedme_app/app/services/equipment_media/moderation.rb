require "digest"
module EquipmentMedia
  class Moderation
    MESSAGES = {
      "accepted" => "Passed automated screening. Listing still requires moderator approval.",
      "needs_review" => "Needs moderator review. You can continue with your listing.",
      "rejected" => "Please remove this photo and choose an equipment-only photo. It was flagged for explicit adult content.",
      "unavailable" => "Image screening is unavailable. Please retry; unchecked photos cannot be published."
    }.freeze
    def self.enabled?
      ENV["REKOGNITION_ENABLED"] == "true"
    end
    def self.policy
      mode = ENV.fetch("REKOGNITION_POLICY", "review_only")
      raise Journeys::Error, "Invalid image screening configuration." unless %w[review_only reject_explicit].include?(mode)
      {mode: mode, review: 60.0, reject: 90.0, equipment: ENV["REKOGNITION_EQUIPMENT_ENABLED"] == "true", version: "v3-strict-equipment"}
    end
    def self.policy_key
      Digest::SHA256.hexdigest(policy.to_json)
    end
    def self.client
      Aws::Rekognition::Client.new(region: ENV.fetch("AWS_REGION", "us-west-2"), retry_limit: 0, http_open_timeout: 3, http_read_timeout: 10)
    end
    def self.decision(labels)
      explicit = labels.any? { |l| l[:confidence] >= policy[:reject] && (["Explicit", "Explicit Nudity", "Explicit Sexual Activity", "Sex Toys"].include?(l[:name]) || ["Explicit", "Explicit Nudity", "Explicit Sexual Activity"].include?(l[:parent_name])) }
      return "rejected" if explicit && policy[:mode] == "reject_explicit"
      labels.any? { |l| l[:confidence] >= policy[:review] } ? "needs_review" : "accepted"
    end
    def self.check(path, account)
      return {state: "unavailable", message: MESSAGES["unavailable"]} unless enabled?
      digest = Digest::SHA256.file(path).hexdigest
      result = nil
      PhotoScreening.transaction(requires_new: true) do
        # Account lock serializes duplicate checks and limits paid requests across workers.
        Account.lock.find(account.id)
        record = PhotoScreening.find_or_initialize_by(account_id: account.id, image_digest: digest, policy_key: policy_key)
        if record.checked_at && record.state != "unavailable"
          result = record
        else
          raise Journeys::Error, "Please wait a minute before retrying photo screening." if record.last_attempt_at && record.last_attempt_at > 1.minute.ago
          attempts = PhotoScreening.where(account_id: account.id).where("last_attempt_at > ?", 1.hour.ago).sum(:attempts)
          raise Journeys::Error, "Photo screening limit reached. Try again in an hour." if attempts >= 30
          record.attempts += 1
          record.last_attempt_at = Time.current
          begin
            response = client.detect_moderation_labels(image: {bytes: File.binread(path)}, min_confidence: policy[:review])
            labels = response.moderation_labels.map { |l| {name: l.name, parent_name: l.parent_name, confidence: l.confidence, taxonomy_level: l.taxonomy_level} }
            state = decision(labels)
            model = response.moderation_model_version
            if policy[:equipment] && state != "rejected"
              objects = client.detect_labels(image: {bytes: File.binread(path)}, min_confidence: 55.0, max_labels: 100, features: ["GENERAL_LABELS"])
              general = objects.labels.map { |l| {source: "equipment", name: l.name, confidence: l.confidence, aliases: Array(l.aliases).map(&:name), instances: Array(l.instances).map { |i| {confidence: i.confidence, area: i.bounding_box ? i.bounding_box.width.to_f * i.bounding_box.height.to_f : 0} }} }
              category = EquipmentClassifier.classify(general)
              state = "rejected" unless category == "recognized"
              labels += general
              model = "moderation:#{model};labels:#{objects.label_model_version}"
            end
            record.assign_attributes(state: state, labels: labels, checked_at: Time.current, model_version: model)
          rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError, Aws::Errors::MissingCredentialsError => error
            Rails.logger.warn("Image moderation unavailable: #{error.class.name}")
            record.state = "unavailable"
          end
          record.save!
          result = record
        end
      end
      message = MESSAGES.fetch(result.state)
      if policy[:equipment]
        saved = result.labels.map(&:deep_symbolize_keys)
        general = saved.select { |l| l[:source] == "equipment" }
        adult_rejection = decision(saved.reject { |l| l[:source] == "equipment" }) == "rejected"
        message = "Please upload a photo of the equipment. This image appears unrelated to the allowed equipment categories." if result.state == "rejected" && !adult_rejection
        message = "We could not recognize allowed equipment in this image. Please remove it and upload a clear photo showing the whole equipment." if result.state == "rejected" && !adult_rejection && EquipmentClassifier.classify(general) == "uncertain"
        message = "Equipment recognized. Passed automated screening; listing still requires moderator approval." if result.state == "accepted"
      end
      {state: result.state, message: message}
    end
    def self.enforce!(photo, account)
      result = check(Photos.path(photo[:sanitized_object_key]), account)
      raise Journeys::Error, result[:message] unless %w[accepted needs_review].include?(result[:state])
      result
    end
  end
end
