module OmnyaConnector
  class Current < ActiveSupport::CurrentAttributes
    attribute :user_guid, :tenant_id, :user_time_zone, :user_language
  end
end
