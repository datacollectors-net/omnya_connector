module OmnyaConnector
  class ApplicationController < ActionController::Base
    include OmnyaConnector::ControllerConcern
  end
end
