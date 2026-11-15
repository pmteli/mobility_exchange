require "test_helper"
require "tempfile"
require Rails.root.join("db/seeds/journeys")
class EquipmentPhotosTest < ActionDispatch::IntegrationTest
  setup do
    load Rails.root.join("db/seeds.rb")
    JourneySeeds.load!
    @donor = Account.find(JourneySeeds.id(1))
    @other = Account.find(JourneySeeds.id(2))
    @moderator = Account.find(JourneySeeds.id(5))
    @files_before = Dir.glob(EquipmentMedia::Photos.root.join('*'))
    @data = {title: "Photo test walker", description: "Fictional equipment for image tests", category_id: Category.find_by!(code: "walkers").id,
      public_locality: "Fremont", condition_code: "good", offer_kind: "gift",
      no_missing_parts_affirmed: "1", fully_functional_affirmed: "1", truthfulness_affirmed: "1"}
  end
  teardown do
    (Dir.glob(EquipmentMedia::Photos.root.join('*')) - @files_before).each { |p| FileUtils.rm_f(p) }
  end
  def upload
    Rack::Test::UploadedFile.new(Rails.root.join("public/simulation/equipment-placeholder.png"), "image/png")
  end
  def create_listing(count = 1)
    Journeys::Workflow.new(@donor).save_listing!(@data.merge(photos: Array.new(count) { upload }))
  end
  def sign_in(number)
    post sign_in_path, params: {mobile: "510555010#{number}"}
    code = SimulatedSmsMessage.where(template_code: "sign_in_otp", recipient: "+1510555010#{number}").order(created_at: :desc).first!.body[/code: (\d+)/, 1]
    post verify_sign_in_path, params: {code: code}
  end
  test "pending photos private to donor and moderator then public only after review" do
    listing = create_listing(2)
    message = SimulatedSmsMessage.where(template_code: "listing_submitted", recipient: "+15105550101").order(created_at: :desc).first!
    assert_equal "FreeDME: Thank you for offering Photo test walker to a neighbor. Your listing is under review. You will be notified when it is published. #{Integrations::SmsLinks.url("listing_submitted")}", message.body
    assert_equal "To be arranged after approval.", ListingRevision.find(listing.current_revision_id).pickup_availability
    pending = ListingPhoto.where(revision_id: listing.current_revision_id).first!
    assert_equal "processing", pending.state
    assert_nil pending.original_object_key
    get equipment_photo_path(pending)
    assert_response :not_found
    sign_in(2)
    get equipment_photo_path(pending)
    assert_response :not_found
    delete sign_out_path
    sign_in(1)
    get equipment_photo_path(pending)
    assert_response :success
    assert_equal "image/jpeg", response.media_type
    assert_includes response.headers['Cache-Control'], 'no-store'
    delete sign_out_path
    sign_in(5)
    get equipment_photo_path(pending)
    assert_response :success
    Journeys::Workflow.new(@moderator).review!(listing.id, "approve", "Reviewed all photos for inappropriate content and private data")
    approved = ListingPhoto.where(revision_id: listing.reload.approved_revision_id).order(:slot)
    assert_equal 2, approved.count
    assert approved.all? { |p| p.state == 'approved' && p.content_reviewed_at }
    delete sign_out_path
    get equipment_photo_path(approved.first)
    assert_response :success
    get equipment_photo_path(pending)
    assert_response :not_found
    get equipment_path(listing)
    assert_select '.gallery-thumb', count: 2
    get equipment_index_path
    assert_select "img[src='#{equipment_photo_path(approved.first)}']"
    Journeys::Workflow.new(@donor).save_listing!(@data.merge(title: 'Changed'), id: listing.id)
    get equipment_photo_path(approved.first)
    assert_response :not_found
  end
  test "edit retains removes and replaces photos without changing history" do
    listing = create_listing(2)
    old_revision = listing.current_revision_id
    old = ListingPhoto.where(revision_id: old_revision).order(:slot).to_a
    Journeys::Workflow.new(@donor).save_listing!(@data.merge(remove_photo_ids: [old.first.id], photos: [upload]), id: listing.id)
    photos = ListingPhoto.where(revision_id: listing.reload.current_revision_id).order(:slot).to_a
    assert_equal 2, photos.length
    assert_equal old.last.sanitized_object_key, photos.first.sanitized_object_key
    refute_equal old.first.sanitized_object_key, photos.last.sanitized_object_key
    assert_equal 2, ListingPhoto.where(revision_id: old_revision).count
    assert_raises(Journeys::Error) { Journeys::Workflow.new(@other).save_listing!(@data.merge(photos: [upload]), id: listing.id) }
    assert_raises(Journeys::Error) { Journeys::Workflow.new(@donor).save_listing!(@data.merge(remove_photo_ids: [SecureRandom.uuid]), id: listing.id) }
  end
  test "photo count and corrupt or oversized uploads fail without partial listing or files" do
    flow = Journeys::Workflow.new(@donor)
    assert_no_difference('Listing.count') do
      assert_raises(Journeys::Error) { flow.save_listing!(@data) }
      assert_raises(Journeys::Error) { create_listing(6) }
      Tempfile.create(['invalid', '.png']) do |file|
        file.binmode; file.write("\x89PNG\r\n\x1a\nnot an image".b); file.flush
        invalid = Rack::Test::UploadedFile.new(file.path, 'image/png')
        assert_raises(Journeys::Error) { flow.save_listing!(@data.merge(photos: [upload, invalid])) }
        assert_equal @files_before.sort, Dir.glob(EquipmentMedia::Photos.root.join('*')).sort
        file.truncate(5.megabytes + 1)
        assert_raises(Journeys::Error) { flow.save_listing!(@data.merge(photos: [Rack::Test::UploadedFile.new(file.path, 'image/png')])) }
      end
    end
  end
  test "metadata removed and orientation applied by actual decoder" do
    Tempfile.create(['metadata', '.jpg']) do |file|
      script = "from PIL import Image; import sys; im=Image.new('RGB',(40,20),'red'); ex=im.getexif(); ex[274]=6; ex[270]='PRIVATE LOCATION'; im.save(sys.argv[1],exif=ex)"
      assert system('python3', '-c', script, file.path)
      result = EquipmentMedia::Photos.prepare(Rack::Test::UploadedFile.new(file.path, 'image/jpeg'))
      path = EquipmentMedia::Photos.path(result[:sanitized_object_key])
      assert system('python3','-c',"from PIL import Image; import sys; im=Image.open(sys.argv[1]); assert im.size==(20,40); assert not im.getexif(); assert 'exif' not in im.info",path.to_s)
      refute_includes File.binread(path), 'PRIVATE LOCATION'
    end
  end
  test "upload errors preserve form values and existing images" do
    sign_in(1)
    post listings_path, params: {listing: @data}
    assert_response :unprocessable_entity
    assert_select 'input#listing_title[value="Photo test walker"]'
    assert_includes response.body, 'between 1 and 5'
    assert_select 'input[type=file][multiple]'
  end
end
