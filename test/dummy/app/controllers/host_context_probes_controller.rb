class HostContextProbesController < ApplicationController
  before_action :require_host_context!

  def show
    render json: {
      user_guid: OmnyaConnector::Current.user_guid,
      tenant_id: OmnyaConnector::Current.tenant_id
    }
  end
end
