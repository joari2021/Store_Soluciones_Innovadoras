Rails.application.routes.draw do
  get '/login', to: 'authentication/sessions#new', as: :new_session
  post '/login', to: 'authentication/sessions#create', as: :sessions
  delete '/logout', to: 'authentication/sessions#destroy', as: :logout

  get '/registro', to: 'authentication/users#new', as: :new_user
  post '/registro', to: 'authentication/users#create', as: :users

  resources :tasa_cambios do
    collection do
      get :bcv_por_fecha
      get :rates_for_date
      post :scrape_bcv
      post :scrape_usdt
    end
  end

  resources :header_notifications, only: %i[destroy]

  resources :productos do
    collection do
      get :search
      get :export_excel
      get :internal_usages, path: 'uso-interno'
      post :internal_usages, action: :create_internal_usage, path: 'uso-interno'
      get :unpack_packs, path: 'destapar-pack'
      post :process_unpack, path: 'destapar-pack'
      get :unpack_histories, path: 'destapar-pack/historial'
      get 'destapar-pack/historial/:id/editar', action: :edit_unpack_history, as: :edit_unpack_history
      patch 'destapar-pack/historial/:id', action: :update_unpack_history, as: :update_unpack_history
      delete 'destapar-pack/historial/:id', action: :destroy_unpack_history, as: :destroy_unpack_history
    end
  end
  resources :profit_margin_presets, path: 'porcentajes-ganancia', only: %i[index create edit update destroy]
  resources :categorias, path: 'categorias', only: %i[index create edit update destroy]
  resources :suppliers do
    member do
      patch :overwrite_product_values
    end
  end
  resources :businesses, path: 'negocios' do
    member do
      post :select
    end
    resources :staff_members, path: 'personal'
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
      post :transfer
      post :register_payment
    end
    resources :account_settlements, path: 'cierres', only: %i[index show create update]
  end
  resources :expenses, path: 'gastos' do
    resources :expense_payments, only: %i[new create]
    post 'convert_amount', to: 'api/expense_payments#convert_amount', on: :member
  end
  resources :debts, path: 'deudas' do
    collection do
      post :create_cliente, path: 'crear-cliente'
    end
    resources :debt_payments, only: %i[new create]
  end
  resources :ventas, only: %i[index create show destroy] do
    member do
      get :delivery_note, path: 'nota-entrega'
    end

    collection do
      get :historial
      get :drafts
      get :products_snapshot
      get :services_snapshot
      get :catalog_products
      get :catalog_services
      get 'drafts/:id', action: :show_draft
      post :save_draft
      patch 'drafts/:id', action: :update_draft
      delete 'drafts/:id', action: :destroy_draft
    end
  end
  resources :cambio_efectivos, path: 'cambios-efectivo', only: %i[index create destroy] do
    collection do
      post :validate
    end
  end
  resources :cash_shifts, path: 'cierres-turno', only: %i[index create show destroy] do
    member do
      patch :close
    end
  end
  resources :purchase_invoices, path: 'facturas-compra' do
    collection do
      get :initial_inventory, path: 'inventario-inicial'
      get :initial_inventory_template, path: 'inventario-inicial/plantilla'
      post :import_initial_inventory, path: 'inventario-inicial/importar'
    end
  end
  resources :managers
  resources :services do
    collection do
      get :export_excel
      get :pending_costs, path: 'sale_services'
      get 'sale_services/:debt_id', action: :pending_cost_detail, as: :pending_cost_detail
      get :pending_cost_rates
      get :printing_prices
      get :recarga_parameters, path: 'parametros-recargas'
      patch 'parametros-recargas/:id', action: :update_recarga_parameters, as: :update_recarga_parameters
      post :pay_pending_cost_line
      delete :remove_pending_cost_line_payment
    end

    member do
      patch :update_printing_prices
    end

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

  if Rails.env.development?
    get 'sandbox/mercantil-c2p-search', to: 'mercantil_c2p_sandbox#index', as: :sandbox_mercantil_c2p_search
    post 'sandbox/mercantil-c2p-search', to: 'mercantil_c2p_sandbox#create'
  end

  resources :appointments, except: %i[index new create]

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
