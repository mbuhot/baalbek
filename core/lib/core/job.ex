defmodule Core.Job do
  @moduledoc """
  A unit of field-service work requested at a `Core.Site`. Tracked through
  one or more `Core.WorkOrder`s.
  """

  use Ash.Resource,
    otp_app: :core,
    domain: Core.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "jobs"
    repo Core.Data.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:title, :description, :status, :scheduled_at, :site_id]
    end

    update :update do
      accept [:title, :description, :status, :scheduled_at]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :description, :string, public?: true

    attribute :status, :atom do
      constraints one_of: [:requested, :scheduled, :in_progress, :completed, :cancelled]
      default :requested
      allow_nil? false
      public? true
    end

    attribute :scheduled_at, :utc_datetime, public?: true
    timestamps()
  end

  relationships do
    belongs_to :site, Core.Site do
      allow_nil? false
      attribute_writable? true
    end

    has_many :work_orders, Core.WorkOrder do
      destination_attribute :job_id
    end
  end
end
