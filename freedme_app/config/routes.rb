Rails.application.routes.draw do
  get "s/:code", to: "sms_links#show", as: :sms_short_link
  get "test-data", to: "test_data#index" if Rails.env.development? || Rails.env.test?
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
    resource :dashboard, only: :show
  end
end
