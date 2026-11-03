abort 'Recording database only' unless ENV['FREEDME_RECORDING_MODE']=='true' && ApplicationRecord.connection.select_value('SELECT current_database()')=='freedme_recording_demo'
def sample_id(n); "019a0000-0000-7000-8000-#{format('%012d',n)}"; end
def check(ok, label); raise "FAILED: #{label}" unless ok; puts "PASS: #{label}"; end
{1000=>'completed',1001=>'reserved',1002=>'declined',1003=>'closed_unavailable',1004=>'completed'}.each do |n,state|
 check(Exchange.where(listing_id:sample_id(n),state:state).exists?, "recording #{n}: #{state}")
end
check(Listing.find(sample_id(1000)).status=='donated','gift listing donated')
loan=Exchange.find_by!(listing_id:sample_id(1004))
check(ExchangeEvent.where(exchange_id:loan.id,event_type:'return_confirmed').exists?,'loan return confirmed')
check(EquipmentQuestion.where(listing_id:sample_id(2000),state:'answered').exists?,'question answered')
new_revision=ListingRevision.find_by!(title:'Demo shower chair — photo screening')
check(Listing.find(new_revision.listing_id).status=='available','new equipment published')
check(ListingPhoto.where(revision_id:new_revision.id).count==2,'only the two accepted photos were submitted')
check(Account.where(display_name:'Casey Demo',status:'active').exists?,'new user registered')
check(IdentityDocumentUpload.where(listing_id:sample_id(2001),state:'failed').exists?,'failed scan retained with no request')
check(IdentityDocumentUpload.where(listing_id:sample_id(2001),state:'extracted').exists?,'scan retry extracted successfully')
check(!Exchange.where(listing_id:sample_id(2001)).exists?,'scan recovery does not submit before consent')
check(Exchange.where(listing_id:sample_id(2002),state:'expired').exists?,'expired request remains in audit history')
check(Exchange.where(listing_id:sample_id(2002),state:'pending').exists?,'retry created fresh pending request')
check(ModeratorTask.where(outcome:'not_handed_off',state:'resolved').exists?,'moderator follow-up resolved')
check(SimulatedSmsMessage.count>20,'simulated notification records exist')
puts 'All recording outcomes verified in isolated database.'
