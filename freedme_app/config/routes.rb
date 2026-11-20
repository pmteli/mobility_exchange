Rails.application.routes.draw do
  get 'staff/notification-mobile', to: 'staff/notification_mobiles#new', as: :staff_notification_mobile
  post 'staff/notification-mobile', to: 'staff/notification_mobiles#create'
  post 'staff/notification-mobile/confirm', to: 'staff/notification_mobiles#confirm', as: :confirm_staff_notification_mobile
  get 'staff/sign-in', to: 'staff_sessions#new', as: :staff_sign_in
  post 'staff/sign-in', to: 'staff_sessions#create'
  get 'staff/verify', to: 'staff_sessions#challenge', as: :staff_verify
  post 'staff/verify', to: 'staff_sessions#verify'
  get 'my-account', to: 'my_account#show', as: :my_account
  get 'my-account/mobile', to: 'my_account#mobile', as: :account_mobile
  post 'my-account/mobile/current', to: 'my_account#start_current_verification', as: :account_mobile_current
  post 'my-account/mobile/verify-current', to: 'my_account#verify_current', as: :account_mobile_verify_current
  post 'my-account/mobile/new-code', to: 'my_account#send_new_code', as: :account_mobile_new_code
  post 'my-account/mobile/confirm', to: 'my_account#confirm_mobile', as: :account_mobile_confirm
  delete 'my-account/mobile', to: 'my_account#cancel_mobile', as: :account_mobile_cancel
  get 'privacy-controls', to: 'privacy_controls#show', as: :privacy_controls
  post 'privacy-controls/deletion', to: 'privacy_controls#request_deletion', as: :privacy_deletion
  post 'admin/privacy/backups', to: 'privacy_controls#create_backup', as: :privacy_backup
  get 'admin/privacy/operations', to: 'privacy_controls#operations', as: :privacy_operations
  get 'admin/privacy', to: 'privacy_controls#review', as: :privacy_review
  patch 'admin/privacy/accounts/:id', to: 'privacy_controls#review_account', as: :privacy_review_account
  get "privacy.html", to: "pages#privacy", as: :privacy_policy
  get "sms-terms.html", to: "pages#sms_terms", as: :sms_terms
  get "sms-consent.html", to: "pages#sms_consent", as: :sms_consent
  patch "sms-preferences", to: "sms_preferences#update", as: :sms_preferences
  post "webhooks/twilio/status", to: "twilio_webhooks#status"
  post "webhooks/twilio/incoming", to: "twilio_webhooks#incoming"
  get "s/:code", to: "sms_links#show", as: :sms_short_link
  get "test-data", to: "test_data#index" if Journeys::Support.enabled?
  get "up" => "rails/health#show", as: :rails_health_check
  root "pages#home"
  get "design-decisions", to: "pages#decisions"
  get "design-preview", to: "design_preview#index", as: :design_preview_index
  get "design-preview/:screen", to: "design_preview#show", as: :design_preview
  get "how-it-works", to: "pages#how", as: :how_it_works
  get "resources", to: "pages#resources"
  get "our-team", to: "pages#team", as: :our_team
  get "sign-in", to: "sessions#new", as: :sign_in
  post "sign-in", to: "sessions#create"
  get "register", to: "sessions#registration", as: :register
  post "register", to: "sessions#register"
  get "sign-in/verify", to: "sessions#challenge", as: :verify_sign_in
  post "sign-in/verify", to: "sessions#verify"
  delete "sign-out", to: "sessions#destroy", as: :sign_out
  get "activity", to: "journeys#index", as: :activity
  get "donate", to: "journeys#new_listing", as: :new_listing
  post "listings", to: "journeys#save_listing", as: :listings
  get "listings/:id/edit", to: "journeys#edit_listing", as: :edit_listing
  patch "listings/:id", to: "journeys#save_listing", as: :update_listing
  post "listings/:id/review", to: "journeys#review", as: :review_listing
  post "listings/:id/reopen", to: "journeys#reopen", as: :reopen_listing
  get "equipment/:id/request", to: "journeys#request_form", as: :new_equipment_request
  post "equipment/:id/identity-document", to: "identity_documents#create", as: :scan_identity_document
  get "identity-documents/:id", to: "identity_documents#show", as: :identity_document
  get "identity-documents/:id/image", to: "identity_documents#image", as: :identity_document_image
  post "identity-documents/:id/confirm", to: "identity_documents#confirm", as: :confirm_identity_document
  post "equipment/:id/request", to: "journeys#create_request", as: :equipment_request
  post "equipment/:id/questions", to: "journeys#ask", as: :equipment_questions
  post "questions/:id/answer", to: "journeys#answer", as: :answer_question
  get "transactions/:id", to: "journeys#transaction", as: :transaction
  post "transactions/:id", to: "journeys#change", as: :change_transaction
  post "moderator/tasks/:id/resolve", to: "journeys#resolve_task", as: :resolve_task
  get "equipment-photos/:id", to: "equipment_photos#show", as: :equipment_photo
  post "photo-screenings", to: "photo_screenings#create", as: :photo_screenings
  resources :equipment, only: [ :index, :show ]
  namespace :donor do
    resource :dashboard, only: :show
  end
  namespace :recipient do
    resource :dashboard, only: :show
  end
  namespace :moderator do
    get "listings/:id", to: "listing_reviews#show", as: :listing_review
    resource :dashboard, only: :show
  end
end
