OmnyaConnector::Engine.routes.draw do
  scope "modules/:module_key" do
    resource :module_context, only: %i[create destroy]
  end
end
