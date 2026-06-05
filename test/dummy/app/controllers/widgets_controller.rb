class WidgetsController < ApplicationController
  def create
    expose_current_host_context_headers
    head :no_content
  end

  def destroy
    expose_current_host_context_headers
    head :no_content
  end

  private

  def expose_current_host_context_headers
    response.set_header("X-Omnya-Current-User-Guid", OmnyaConnector::Current.user_guid) if OmnyaConnector::Current.user_guid.present?
    response.set_header("X-Omnya-Current-Tenant-Id", OmnyaConnector::Current.tenant_id) if OmnyaConnector::Current.tenant_id.present?
  end
end
