Rails.application.routes.draw do
  resources :tasa_cambios do
    collection do
      get :bcv_por_fecha
      post :scrape_bcv
      post :scrape_usdt
    end
  end

  namespace :authentication, path: '', as: '' do
    resources :users, only: %i[new create], path: '/register', path_names: { new: '/' }
    resources :sessions, only: %i[new create destroy], path: '/login', path_names: { new: '/' }
  end

  resources :productos do
    collection do
      get :search
    end
  end
  resources :suppliers do
    member do
      patch :overwrite_product_values
    end
  end
  resources :businesses, path: 'negocios' do
    member do
      post :select
    end
  end
  resources :clientes do
    collection do
      get :search
    end
  end
  resources :accounts, path: 'cuentas' do
    member do
      patch :set_primary
      patch :unset_primary
    end
    resources :account_settlements, path: 'cierres', only: %i[index show create update]
  end
  resources :expenses, path: 'gastos' do
    resources :expense_payments, only: %i[new create]
  end
  resources :debts, path: 'deudas' do
    collection do
      post :create_cliente, path: 'crear-cliente'
    end
    resources :debt_payments, only: %i[new create]
  end
  resources :ventas, only: %i[index create show] do
    collection do
      get :historial
    end
  end
  resources :purchase_invoices, path: 'facturas-compra'
  resources :managers
  resources :services do
    resources :service_managers, only: %i[new create edit update destroy]
  end
  resources :system_services
  resources :serie_tvs
  resources :generos, except: :show
  resources :plataforma_peliculas, except: :show
  resources :juegos
  resources :animes
  resources :peliculas
  root 'productos#index' # ← Esto define la ruta de inicio

  resources :saime_users do
    collection do
      post :assign
    end
    resources :appointments, only: %i[index new create]
  end

  resources :appointments, except: %i[index new create]

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
