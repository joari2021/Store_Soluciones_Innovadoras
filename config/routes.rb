Rails.application.routes.draw do
  resource :tasa_cambio, only: [:edit, :update]

  namespace :authentication, path: "", as: "" do
    resources :users, only: [:new, :create], path: "/register", path_names: { new: "/" }
    resources :sessions, only: [:new, :create, :destroy], path: "/login", path_names: { new: "/" }
  end

  resources :productos
  resources :services
  resources :system_services
  resources :serie_tvs
  resources :generos, except: :show
  resources :plataforma_peliculas, except: :show
  resources :juegos
  resources :animes
  resources :peliculas
  root "peliculas#index" # ← Esto define la ruta de inicio

  resources :saime_users do
    collection do
      post :assign
    end
    resources :appointments, only: [:index, :new, :create]
  end

  resources :appointments, except: [:index, :new, :create]

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
