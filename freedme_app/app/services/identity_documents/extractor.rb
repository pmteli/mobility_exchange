module IdentityDocuments
  class Extractor
    FIELDS = %w[first_name last_name home_address zip_code].freeze
    QUERIES = {
      'full_name' => "What is the full name of the individual customer or account holder?",
      'service_name' => "What is the name under Service For?",
      'home_address' => "What is the customer's residential service address, including street, city and state, not the utility company's address?",
      'zip_code' => "What is the ZIP code of the customer's residential service address, not the utility company's ZIP code?"
    }.freeze
    def initialize(client: nil)
      @client = client || Aws::Textract::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'), retry_limit: 0, http_open_timeout: 3, http_read_timeout: 25)
    end
    def extract(bytes, kind)
      if kind == 'government_id'
        response = @client.analyze_id(document_pages: [{bytes: bytes}])
        raw = Array(response.identity_documents).flat_map { |document| Array(document.identity_document_fields) }.to_h { |f| [f.type&.text, f.value_detection&.text.to_s.strip] }
        fields = {'first_name' => raw['FIRST_NAME'], 'last_name' => raw['LAST_NAME'],
          'home_address' => [raw['ADDRESS'],raw['CITY_IN_ADDRESS'],raw['STATE_IN_ADDRESS']].compact.reject(&:blank?).join(', '), 'zip_code' => raw['ZIP_CODE_IN_ADDRESS']}
      else
        response = @client.analyze_document(document: {bytes: bytes}, feature_types: ['QUERIES'],
          queries_config: {queries: QUERIES.map { |key,text| {text: text, alias: key} }})
        response_blocks = Array(response.blocks)
        blocks = response_blocks.index_by(&:id)
        fields = response_blocks.select { |b| b.block_type == 'QUERY' }.to_h do |query|
          # Unanswered Textract queries can omit relationships entirely.
          ids = Array(query.relationships).select { |r| r.type == 'ANSWER' }.flat_map { |r| Array(r.ids) }
          [query.query&.alias, ids.filter_map { |id| answer = blocks[id]; answer.text if answer&.block_type == 'QUERY_RESULT' }.join(' ')]
        end
        full_name = fields['service_name'].presence || fields['full_name'].to_s
        fields['first_name'], fields['last_name'] = full_name.strip.split(/\s+/, 2)
        # Only recover ZIP from the selected customer address, never the bill's
        # other text (which may contain the utility company's postal address).
        if fields['zip_code'].blank?
          fields['zip_code'] = fields['home_address'].to_s[/\b\d{5}(?:-\d{4})?\s*\z/].to_s.strip
        end
      end
      # Keep only the four requested fields. Never persist raw provider responses,
      # document numbers, dates of birth, photos of faces, or financial fields.
      fields = FIELDS.to_h { |key| [key, fields[key].to_s.strip] }
      fields['zip_code'] = fields['zip_code'].sub(/\A(\d{5})(\d{4})\z/, '\\1-\\2')
      unless fields.values.all?(&:present?) && fields.values.all? { |v| v.length <= 500 } && fields['zip_code'].match?(/\A\d{5}(?:-\d{4})?\z/)
        raise Journeys::Error, 'We could not extract your full name, residential address and ZIP code. Please upload a clear utility bill or current-address government ID. A passport without an address is not sufficient.'
      end
      fields
    end
  end
end
