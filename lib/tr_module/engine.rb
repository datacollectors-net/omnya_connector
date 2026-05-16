module TrModule
  class Engine < ::Rails::Engine
    isolate_namespace TrModule
  end
end
