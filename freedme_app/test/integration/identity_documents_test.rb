require 'test_helper'
require Rails.root.join('db/seeds/journeys')
class IdentityDocumentsTest < ActionDispatch::IntegrationTest
  setup do
    load Rails.root.join('db/seeds.rb')
    JourneySeeds.load!
    @actor = Account.find(JourneySeeds.id(3))
    @donor = Account.find(JourneySeeds.id(1))
    @moderator = Account.find(JourneySeeds.id(5))
    @listing = Listing.find(JourneySeeds.id(1000))
    Journeys::Workflow.new(@moderator).review!(@listing.id, 'approve', 'Sample test review')
    @listing.reload
    ENV['TEXTRACT_ENABLED'] = 'true'
    Aws.config[:textract] = {stub_responses: true}
    @fields = {'first_name'=>'Maya', 'last_name'=>'Patel','home_address'=>'123 Example Street, Fremont, CA','zip_code'=>'94536'}
  end
  teardown do
    ENV.delete('TEXTRACT_ENABLED')
    Aws.config.delete(:textract)
  end
  def login(number)
    delete sign_out_path
    post sign_in_path, params: {mobile: "510555010#{number}"}
    code = SimulatedSmsMessage.where(template_code:'sign_in_otp',recipient:"+1510555010#{number}").order(created_at: :desc).first!.body[/code: (\d+)/,1]
    post verify_sign_in_path, params: {code: code}
  end
  def scan_record
    IdentityDocumentUpload.create!(account: @actor, listing: @listing, revision_id: @listing.approved_revision_id,
      document_kind:'utility_bill',state:'extracted',fields_ciphertext:IdentityDocuments::Vault.encrypt(@fields.to_json),
      image_ciphertext:IdentityDocuments::Vault.encrypt('fictional image bytes'),purge_due_at:7.days.from_now)
  end
  test 'private fields require confirmation; donor gets only name and zip with qualified label' do
    upload = scan_record
    login(3)
    get identity_document_path(upload)
    assert_response :success
    assert_includes response.body, '123 Example Street'
    assert_no_difference 'Exchange.count' do
      post confirm_identity_document_path(upload), params:{consent:'1'}
    end
    assert_difference 'Exchange.count',1 do
      post confirm_identity_document_path(upload), params:{confirmed:'1',consent:'1',first_name:'Maya',last_name:'Patel'}
    end
    exchange = Exchange.find(upload.reload.exchange_id)
    assert_no_difference 'Exchange.count' do
      post confirm_identity_document_path(upload), params:{confirmed:'1',consent:'1',first_name:'Maya',last_name:'Patel'}
    end
    login(1)
    get identity_document_image_path(upload)
    assert_response :not_found
    get identity_document_path(upload)
    assert_response :not_found
    get transaction_path(exchange)
    assert_response :success
    assert_includes response.body,'Verified'
    assert_includes response.body,'Verified Recipient Identity'
    refute_includes response.body,'not been independently verified'
    assert_includes response.body,'Maya Patel'
    refute_includes response.body,'123 Example Street'
    login(5)
    get identity_document_image_path(upload)
    assert_response :success
    assert_includes response.headers['Cache-Control'],'no-store'
  end
  test 'expired images are blocked and purged without removing extracted fields' do
    upload = scan_record
    upload.update!(purge_due_at: 1.second.ago)
    login(3)
    get identity_document_image_path(upload)
    assert_response :not_found
    assert_no_difference 'Exchange.count' do
      post confirm_identity_document_path(upload),params:{confirmed:'1',consent:'1',first_name:'Maya',last_name:'Patel'}
    end
    IdentityDocuments::Vault.purge!
    assert_nil upload.reload.image_ciphertext
    assert upload.image_deleted_at
    assert_equal @fields,upload.extracted_fields
  end
  test 'ID extraction allowlists only requested fields and refuses missing addresses' do
    client = Aws::Textract::Client.new(stub_responses:true)
    fields = {'FIRST_NAME'=>'Maya','LAST_NAME'=>'Patel','ADDRESS'=>'123 Example Street','CITY_IN_ADDRESS'=>'Fremont','STATE_IN_ADDRESS'=>'CA','ZIP_CODE_IN_ADDRESS'=>'945361234','DOCUMENT_NUMBER'=>'do not retain'}
    data = fields.map { |key,value| {type:{text:key},value_detection:{text:value}} }
    client.stub_responses(:analyze_id,{identity_documents:[{identity_document_fields:data}]})
    assert_equal @fields.merge('zip_code'=>'94536-1234'),IdentityDocuments::Extractor.new(client:client).extract('fake','government_id')
    client.stub_responses(:analyze_id,{identity_documents:[{identity_document_fields:data.first(2)}]})
    assert_raises(Journeys::Error) { IdentityDocuments::Extractor.new(client:client).extract('fake','government_id') }
  end
  test 'utility bill queries use only linked answers' do
    blocks = {'full_name'=>'Maya Patel', 'home_address'=>@fields['home_address'], 'zip_code'=>'94536'}.flat_map.with_index do |(key,value),i|
      [{id:"q#{i}",block_type:'QUERY',query:{alias:key,text:'Question'},relationships:[{type:'ANSWER',ids:["a#{i}"]}]},
       {id:"a#{i}",block_type:'QUERY_RESULT',text:value}]
    end
    client=Aws::Textract::Client.new(stub_responses:true)
    client.stub_responses(:analyze_document,{blocks:blocks})
    assert_equal @fields,IdentityDocuments::Extractor.new(client:client).extract('fake','utility_bill')
  end
  test 'direct simulation bypass is disabled and failed scan sends no donor request' do
    assert_raises(Journeys::Error) { Journeys::Workflow.new(@actor).request!(@listing.id,consent:'1',outcome:'pass') }
    login(3)
    assert_no_difference 'Exchange.count' do
      post scan_identity_document_path(@listing),params:{processing_consent:'1',document_kind:'government_id',identity_document:Rack::Test::UploadedFile.new(Rails.root.join('public/simulation/equipment-placeholder.png'),'image/png')}
    end
    assert_response :redirect
    assert_equal 'failed',IdentityDocumentUpload.last.state
    assert IdentityDocumentUpload.last.image_ciphertext
  end
  test 'document upload accepts 20 MB and rejects larger input before scanning' do
    path = Rails.root.join('public/simulation/equipment-placeholder.png')
    Tempfile.create(['large-document', '.png']) do |file|
      file.binmode
      file.write(File.binread(path))
      file.truncate(20.megabytes)
      file.flush
      upload = Rack::Test::UploadedFile.new(file.path, 'image/png')
      assert_difference 'IdentityDocumentUpload.count', 1 do
        # Stubbed Textract returns no fields, but intake must reach extraction.
        error = assert_raises(Journeys::Error) { IdentityDocuments::Intake.scan!(@actor, @listing, upload, 'utility_bill') }
        assert_includes error.message, 'could not extract'
      end
      assert IdentityDocumentUpload.order(created_at: :desc).first.image_ciphertext
      file.truncate(20.megabytes + 1)
      file.flush
      upload = Rack::Test::UploadedFile.new(file.path, 'image/png')
      assert_no_difference 'IdentityDocumentUpload.count' do
        error = assert_raises(Journeys::Error) { IdentityDocuments::Intake.scan!(@actor, @listing, upload, 'utility_bill') }
        assert_includes error.message, 'up to 20 MB'
      end
    end
  end

  test 'unanswered utility bill queries return a friendly error and no donor request' do
    # AWS omits Relationships when it cannot answer a query.
    unanswered = {id: 'q1', block_type: 'QUERY', query: {alias: 'first_name', text: 'First name?'}}
    Aws.config[:textract] = {stub_responses: {analyze_document: {blocks: [unanswered]}}}
    login(3)
    assert_no_difference 'Exchange.count' do
      post scan_identity_document_path(@listing), params: {
        processing_consent: '1', document_kind: 'utility_bill',
        identity_document: Rack::Test::UploadedFile.new(Rails.root.join('public/simulation/equipment-placeholder.png'), 'image/png')}
    end
    assert_redirected_to new_equipment_request_path(@listing)
    assert_includes flash[:alert], 'could not extract'
    assert_equal 'failed', IdentityDocumentUpload.order(created_at: :desc).first.state
  end

  test 'missing answer ids and dangling answers are treated as incomplete extraction' do
    client = Aws::Textract::Client.new(stub_responses: true)
    [nil, [], [{type: 'ANSWER'}], [{type: 'ANSWER', ids: ['missing']}]].each do |relationships|
      client.stub_responses(:analyze_document, {blocks: [{id: 'q', block_type: 'QUERY',
        query: {alias: 'first_name', text: 'Name?'}, relationships: relationships}]})
      error = assert_raises(Journeys::Error) { IdentityDocuments::Extractor.new(client: client).extract('fake', 'utility_bill') }
      assert_includes error.message, 'could not extract'
    end
  end

  test 'bill full name is split once and missing ZIP comes only from service address' do
    values = {'service_name'=>'Sample Person', 'home_address'=>'123 Example Street, Fremont, CA 94536-1234'}
    blocks = values.flat_map.with_index { |(key,value),i| [
      {id:"q#{i}",block_type:'QUERY',query:{alias:key,text:'Question'},relationships:[{type:'ANSWER',ids:["a#{i}"]}]},
      {id:"a#{i}",block_type:'QUERY_RESULT',text:value}] }
    client = Aws::Textract::Client.new(stub_responses: true)
    client.stub_responses(:analyze_document, {blocks: blocks})
    fields = IdentityDocuments::Extractor.new(client: client).extract('fake','utility_bill')
    assert_equal 'Sample', fields['first_name']
    assert_equal 'Person', fields['last_name']
    assert_equal '94536-1234', fields['zip_code']
    blocks.last[:text] = '123 Example Street, Fremont, CA'
    blocks << {id:'unrelated',block_type:'LINE',text:'Utility company ZIP 95899'}
    client.stub_responses(:analyze_document, {blocks: blocks})
    assert_raises(Journeys::Error) { IdentityDocuments::Extractor.new(client: client).extract('fake','utility_bill') }
  end

  test 'requester can correct name but cannot submit blank names' do
    @fields.merge!('first_name'=>'Mary', 'last_name'=>'Jane Smith')
    upload = scan_record
    login(3)
    assert_no_difference 'Exchange.count' do
      post confirm_identity_document_path(upload), params:{confirmed:'1',consent:'1',first_name:'',last_name:'Person'}
    end
    assert_redirected_to identity_document_path(upload)
    assert_equal @fields, upload.reload.extracted_fields
    assert_difference 'Exchange.count', 1 do
      post confirm_identity_document_path(upload), params:{confirmed:'1',consent:'1',first_name:'Mary Jane',last_name:'Smith'}
    end
    assert_equal 'Mary Jane', upload.reload.extracted_fields['first_name']
    assert_equal 'Smith', upload.extracted_fields['last_name']
    assert upload.name_corrected?
    assert_equal 'Mary', upload.extracted_fields['_extracted_name']['first_name']
    login(1)
    get transaction_path(upload.exchange_id)
    assert_includes response.body, 'Verified Recipient Identity'
    refute_includes response.body, 'Requester-corrected'
  end

end
