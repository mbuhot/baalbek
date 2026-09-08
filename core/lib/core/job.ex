defmodule Core.Job do
  @moduledoc """
  A unit of field-service work requested at a `Core.Site`, tracked through one or more `Core.WorkOrder`s.
  """

  use Ash.Resource,
    otp_app: :core,
    domain: Core,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]

  json_api do
    type "job"

    routes do
      base("/jobs")

      get(:read)
      index :read
      post(:create)
      patch(:update)
      delete(:destroy)
    end
  end

  postgres do
    table "jobs"
    repo Core.Data.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Requests a new job at a site."
      accept [:title, :description, :status, :scheduled_at, :site_id]
    end

    update :update do
      description "Updates a job's title, description, status, or schedule."
      accept [:title, :description, :status, :scheduled_at]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string,
      allow_nil?: false,
      public?: true,
      description: "A short summary of the requested work."

    attribute :description, :string,
      public?: true,
      description: "Further detail about the requested work."

    attribute :status, :atom do
      constraints one_of: [:requested, :scheduled, :in_progress, :completed, :cancelled]
      default :requested
      allow_nil? false
      public? true
      description "The job's current stage in its lifecycle."
    end

    attribute :scheduled_at, :utc_datetime,
      public?: true,
      description: "When the job is scheduled to be carried out."

    create_timestamp :inserted_at,
      type: :utc_datetime,
      public?: true,
      description: "When this job was created."

    update_timestamp :updated_at,
      type: :utc_datetime,
      public?: true,
      description: "When this job was last updated."
  end

  relationships do
    belongs_to :site, Core.Site do
      allow_nil? false
      attribute_writable? true
      attribute_public? true
      description "The site where this job takes place."
    end

    has_many :work_orders, Core.WorkOrder do
      destination_attribute :job_id
      description "This job's work orders."
    end
  end
end
