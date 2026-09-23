Rails.application.routes.draw do
  get "up", to: "rails/health#show", as: :rails_health_check
  root "catalog#index"
  get "photo-credits", to: "photo_credits#index", as: :photo_credits
  get "equipment", to: "catalog#index", as: :catalogue
  get "equipment/:id", to: "catalog#show", as: :catalog_item
  get "pages/:slug", to: "pages#show", as: :page
  post "auth/google", to: "google_sessions#start", as: :google_sign_in
  get "auth/google/callback", to: "google_sessions#callback"
  get "google_registration/new", to: "google_sessions#new", as: :new_google_registration
  post "google_registration", to: "google_sessions#create", as: :google_registration
  resource :session, only: [:new, :create, :destroy]
  resource :registration, only: [:new, :create]
  resources :password_resets, only: [:new, :create, :edit, :update], param: :token
  get "verification/:token", to: "verifications#show", as: :verification
  post "verification/:token", to: "verifications#update"
  resource :verification_request, only: [:new, :create]
  resource :account, only: [:show, :edit, :update]
  get "profile_email/:token", to: "profile_emails#show", as: :profile_email
  post "profile_email/:token", to: "profile_emails#update"
  resources :money_donations, path: "donate-money", only: [:index, :new, :create, :show]
  post "webhooks/stripe", to: "stripe_webhooks#create"
  resources :donations, only: [:new, :create, :show] do
    resources :photos, only: :show, controller: "donation_photos"
    post :sign, on: :member
    post :book, on: :member
  end
  resources :equipment_requests, path: "requests", only: [:new, :create, :show] do
    post :sign, on: :member
    post :book, on: :member
  end
  resources :shifts, only: :index do
    post :join, on: :member
    delete :leave, on: :member
  end
  resource :volunteer_application, only: [:new, :create]
  get "documents/:id", to: "documents#show", as: :document
  namespace :staff do
    root "dashboard#index"
    resources :equipment, only: [:index, :new, :create, :show, :edit, :update] do
      post :process_item, on: :member
    end
    resources :requests, only: [:index, :show, :update] do
      post :reserve, on: :member
      post :release, on: :member
      post :cancel_reservation, on: :member
    end
    resources :donations, only: [:index, :show, :update] do
      post :receive_item, on: :member
    end
    resources :volunteers, only: [:index, :update]
    resources :shifts, only: [:index, :new, :create, :update]
    resources :slots, only: [:index, :new, :create, :update]
    resources :pages, only: [:index, :edit, :update]
    get "reports", to: "reports#index"
  end
end
