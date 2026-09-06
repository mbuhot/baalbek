defmodule Server.Api.WorkOrder do
  @moduledoc "JSON:API resource for `core`'s `Core.WorkOrder`, backed by `Core`'s exported work-order functions."

  use Ash.Resource,
    domain: Server.Api,
    extensions: [AshJsonApi.Resource]

  json_api do
    type "work_order"

    routes do
      base "/work_orders"

      get :read
      index :read
      post :create
      patch :update
      delete :destroy
    end
  end

  actions do
    read :read do
      primary? true

      description "Lists or fetches work orders via `Core.list_work_orders/0` and `Core.get_work_order/1`."

      manual Server.Api.WorkOrder.Manual
    end

    create :create do
      description "Opens a new work order against a job via `Core.create_work_order/1`."
      accept [:summary, :status, :completed_at, :job_id]
      manual Server.Api.WorkOrder.Manual
    end

    update :update do
      description "Updates a work order's summary, status, or completion time via `Core.update_work_order/2`."
      accept [:summary, :status, :completed_at]
      manual Server.Api.WorkOrder.Manual
    end

    destroy :destroy do
      description "Removes a work order via `Core.destroy_work_order/1`."
      manual Server.Api.WorkOrder.Manual
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :summary, :string,
      allow_nil?: false,
      public?: true,
      description: "A short summary of the work carried out."

    attribute :status, :atom do
      constraints one_of: [:open, :in_progress, :completed]
      default :open
      allow_nil? false
      public? true
      description "The work order's current stage in its lifecycle."
    end

    attribute :completed_at, :utc_datetime,
      public?: true,
      description: "When this work order was completed."

    attribute :job_id, :uuid,
      allow_nil?: false,
      public?: true,
      description: "The id of the job this work order belongs to."

    attribute :inserted_at, :utc_datetime,
      writable?: false,
      public?: true,
      description: "When this work order was created."

    attribute :updated_at, :utc_datetime,
      writable?: false,
      public?: true,
      description: "When this work order was last updated."
  end
end
