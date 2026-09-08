defmodule Core.WorkOrder do
  @moduledoc """
  A discrete piece of work carried out, or to be carried out, against a `Core.Job`.

  A job can have one or more work orders — e.g. an initial visit plus a
  follow-up.
  """

  use Ash.Resource,
    otp_app: :core,
    domain: Core,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]

  json_api do
    type "work_order"

    routes do
      base("/work_orders")

      get(:read)
      index :read
      post(:create)
      patch(:update)
      delete(:destroy)
    end
  end

  postgres do
    table "work_orders"
    repo Core.Data.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Opens a new work order against a job."
      accept [:summary, :status, :completed_at, :job_id]
    end

    update :update do
      description "Updates a work order's summary, status, or completion time."
      accept [:summary, :status, :completed_at]
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

    create_timestamp :inserted_at,
      type: :utc_datetime,
      public?: true,
      description: "When this work order was created."

    update_timestamp :updated_at,
      type: :utc_datetime,
      public?: true,
      description: "When this work order was last updated."
  end

  relationships do
    belongs_to :job, Core.Job do
      allow_nil? false
      attribute_writable? true
      attribute_public? true
      description "The job this work order belongs to."
    end
  end
end
