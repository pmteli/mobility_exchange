# Update only the old seeded illustration wording; never overwrite donor descriptions.
unless Rails.env.test? || Rails.env.development? || (ENV['DEPLOYMENT_STAGE'] == 'test' && ENV['APP_HOST'] == 'test.mobilityexchange.org')
  raise 'Sample description update is restricted to the test site.'
end
Workflow.run do
  old = 'The picture is a category illustration; it does not show a real donated item.'
  replacement = 'The picture is a representative equipment photo; it does not show this specific item.'
  Equipment.where("id LIKE 'sample-equipment-%'").find_each do |item|
    item.update!(description: item.description.sub(old, replacement)) if item.description&.include?(old)
  end
end
puts 'Sample equipment photo descriptions updated.'
