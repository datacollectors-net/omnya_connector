Rails.application.routes.draw do
  resources :widgets, only: %i[create destroy]
  mount OmnyaConnector::Engine => "/"
end
