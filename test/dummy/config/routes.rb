Rails.application.routes.draw do
  resources :widgets, only: %i[create destroy]
  resource :host_context_probe, only: %i[show]
  mount OmnyaConnector::Engine => "/"
end
