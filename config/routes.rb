TrModule::Engine.routes.draw do
  resource :module_context, only: %i[create destroy]
end
