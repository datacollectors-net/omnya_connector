Rails.application.routes.draw do
  mount TrModule::Engine => "/"
end
