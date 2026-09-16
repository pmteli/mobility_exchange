# Sample equipment

Migration 20260915000000_seed_test_equipment creates 25 fictional available items: 6 wheelchairs, 7 walkers/rollators, 5 shower chairs, and 7 canes/crutches.

Deploy with bin/rails db:migrate. Repeat explicitly with SEED_TEST_EQUIPMENT=1 bin/rails db:seed. Both paths use db/seeds/test_equipment.rb. Supported environments: development, test, or DEPLOYMENT_STAGE=test with APP_HOST=test.mobilityexchange.org. The migration skips live production.

Stable IDs preserve existing records and workflow changes on repeat runs. All descriptions, locations and processing evidence are fictional. Pictures use six local SVG category illustrations under public/design, not actual donation photographs. No external image service is required.

Rollback raises IrreversibleMigration because items may have dependent requests. Review those dependencies before removal.

Local validation: migration succeeded; 1 test and 10 assertions passed for category counts, availability, repeatability and image assets. AWS migration applied successfully on 2026-09-15. Verified 25 available sample items (6 wheelchairs, 7 walkers/rollators, 5 bathroom safety, 7 walking aids), repeat seed preserved inventory, and the catalog plus all six SVG URLs loaded over HTTPS. Temporary deployment SSH key removed.
