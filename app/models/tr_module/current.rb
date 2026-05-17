module TrModule
  class Current < ActiveSupport::CurrentAttributes
    attribute :user_guid, :tenant_id
  end
end
