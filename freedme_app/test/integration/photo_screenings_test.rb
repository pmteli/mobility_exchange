require "test_helper"
class PhotoScreeningsTest < ActionDispatch::IntegrationTest
  setup do
    load Rails.root.join("db/seeds.rb")
    JourneySeeds.load!
    @donor = Account.find(JourneySeeds.id(1))
    @before = Dir.glob(EquipmentMedia::Photos.root.join('*'))
    @photo = EquipmentMedia::Photos.prepare(upload)
    @path = EquipmentMedia::Photos.path(@photo[:sanitized_object_key])
  end
  teardown do
    (Dir.glob(EquipmentMedia::Photos.root.join('*')) - @before).each { |path| FileUtils.rm_f(path) }
  end
  def upload
    Rack::Test::UploadedFile.new(Rails.root.join('public/simulation/equipment-placeholder.png'), 'image/png')
  end
  def reply(labels=[])
    Aws.config[:rekognition] = {stub_responses: {detect_moderation_labels: {moderation_labels: labels, moderation_model_version: 'test-v7'}}}
  end
  def check
    EquipmentMedia::Moderation.check(@path, @donor)
  end
  test "clean image cached and policy changes invalidate decision" do
    reply
    assert_equal 'accepted', check[:state]
    record=PhotoScreening.last
    assert_equal 1, record.attempts
    reply([{name:'Explicit',confidence:99.0,taxonomy_level:1}])
    assert_equal 'accepted', check[:state]
    assert_equal 1, record.reload.attempts
    ENV['REKOGNITION_POLICY']='reject_explicit'
    assert_equal 'rejected', check[:state]
    assert_equal 2, PhotoScreening.where(account_id:@donor.id).count
  end
  test "review only flags explicit without rejecting and reject policy honors confidence" do
    reply([{name:'Explicit',confidence:99.0,taxonomy_level:1}])
    assert_equal 'needs_review',check[:state]
    ENV['REKOGNITION_POLICY']='reject_explicit'
    reply([{name:'Explicit Nudity',parent_name:'Explicit',confidence:89.0,taxonomy_level:2}])
    assert_equal 'needs_review',check[:state]
  end
  test "non adult flag needs review even at high confidence" do
    ENV['REKOGNITION_POLICY']='reject_explicit'
    reply([{name:'Violence',confidence:98.0,taxonomy_level:1}])
    assert_equal 'needs_review',check[:state]
  end
  test "AWS outage cannot be mistaken for pass and retries are throttled" do
    Aws.config[:rekognition]={stub_responses:{detect_moderation_labels:'AccessDeniedException'}}
    assert_equal 'unavailable',check[:state]
    assert_raises(Journeys::Error){check}
    assert_equal 1,PhotoScreening.last.attempts
    assert_raises(Journeys::Error){EquipmentMedia::Moderation.enforce!(@photo,@donor)}
  end
  test "disabled integration blocks unchecked photos" do
    ENV['REKOGNITION_ENABLED']='false'
    assert_equal 'unavailable',check[:state]
    assert_no_difference('PhotoScreening.count'){assert_raises(Journeys::Error){EquipmentMedia::Moderation.enforce!(@photo,@donor)}}
  end
  test "endpoint requires login returns status and removes temporary file" do
    post photo_screenings_path,params:{photo:upload}
    assert_redirected_to sign_in_path
    post sign_in_path,params:{mobile:'5105550101'}
    code=SimulatedSmsMessage.where(template_code:'sign_in_otp',recipient:'+15105550101').order(created_at: :desc).first!.body[/code: (\d+)/,1]
    post verify_sign_in_path,params:{code:code}
    reply
    before=Dir.glob(EquipmentMedia::Photos.root.join('*')).sort
    post photo_screenings_path,params:{photo:upload}
    assert_response :success
    assert_equal 'accepted',response.parsed_body['state']
    assert_equal before,Dir.glob(EquipmentMedia::Photos.root.join('*')).sort
  end
  test "submission cannot bypass rejected preflight" do
    ENV['REKOGNITION_POLICY']='reject_explicit'
    reply([{name:'Explicit',confidence:99.0,taxonomy_level:1}])
    data={title:'Test walker',description:'Test description',category_id:Category.find_by!(code:'walkers').id,public_locality:'Fremont',condition_code:'good',offer_kind:'gift',pickup_availability:'Library',no_missing_parts_affirmed:'1',fully_functional_affirmed:'1',truthfulness_affirmed:'1',photos:[upload]}
    assert_no_difference('Listing.count'){assert_raises(Journeys::Error){Journeys::Workflow.new(@donor).save_listing!(data)}}
    assert_equal 'rejected',PhotoScreening.last.state
  end
  test "equipment classifier distinguishes recognized unrelated and uncertain photos" do
    classifier = EquipmentMedia::EquipmentClassifier
    assert_equal 'recognized', classifier.classify([{name:'Wheelchair',confidence:90.0}])
    assert_equal 'uncertain', classifier.classify([])
    assert_equal 'uncertain', classifier.classify([{name:'Wheel',confidence:99.0}])
    dog = {name:'Dog',confidence:99.0,instances:[{confidence:99.0,area:0.7}]}
    assert_equal 'unrelated', classifier.classify([dog])
    assert_equal 'uncertain', classifier.classify([dog.merge(instances:[{confidence:99.0,area:0.1}])])
    assert_equal 'uncertain', classifier.classify([dog, {name:'Wheelchair',confidence:60.0}])
    assert_equal 'recognized', classifier.classify([dog, {name:'Crutches',confidence:95.0}])
    assert_equal 'uncertain', classifier.classify([{name:'Chair',confidence:99.0}])
  end
  test "equipment checks reject unrelated content and cache the correct reason" do
    ENV['REKOGNITION_EQUIPMENT_ENABLED']='true'
    Aws.config[:rekognition] = {stub_responses: {
      detect_moderation_labels: {moderation_labels:[],moderation_model_version:'7'},
      detect_labels: {labels:[{name:'Dog',confidence:99.0,instances:[{confidence:99.0,bounding_box:{width:0.9,height:0.9,left:0.0,top:0.0}}]}],label_model_version:'3'}
    }}
    assert_equal 'rejected',check[:state]
    assert_includes check[:message], 'appears unrelated'
    assert_equal 1,PhotoScreening.last.attempts
    assert_raises(Journeys::Error){EquipmentMedia::Moderation.enforce!(@photo,@donor)}
  end
  test "missing equipment evidence is rejected and AWS label failure fails closed" do
    ENV['REKOGNITION_EQUIPMENT_ENABLED']='true'
    Aws.config[:rekognition] = {stub_responses: {detect_moderation_labels:{moderation_labels:[]},detect_labels:{labels:[]}}}
    assert_equal 'rejected',check[:state]
    assert_includes check[:message], 'could not recognize allowed equipment'
    assert_raises(Journeys::Error){EquipmentMedia::Moderation.enforce!(@photo,@donor)}
    PhotoScreening.delete_all
    Aws.config[:rekognition] = {stub_responses: {detect_moderation_labels:{moderation_labels:[]},detect_labels:'AccessDeniedException'}}
    assert_equal 'unavailable',check[:state]
  end

end
