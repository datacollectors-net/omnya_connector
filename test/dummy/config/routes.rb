Rails.application.routes.draw do
  mount OmnyaConnector::Engine => "/"
end
