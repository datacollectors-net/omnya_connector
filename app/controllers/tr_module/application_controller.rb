module TrModule
  class ApplicationController < ActionController::Base
    include TrModule::ControllerConcern
  end
end
