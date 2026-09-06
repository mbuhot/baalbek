defmodule Core.Site do
  @moduledoc """
  A physical location belonging to a `Core.Customer`, where `Core.Job`s
  happen.
  """

  use Ash.Resource,
    otp_app: :core,
    domain: Core.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "sites"
    repo Core.Data.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :address, :customer_id]
    end

    update :update do
      accept [:name, :address]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :address, :string, public?: true
    timestamps()
  end

  relationships do
    belongs_to :customer, Core.Customer do
      allow_nil? false
      attribute_writable? true
    end

    has_many :jobs, Core.Job do
      destination_attribute :site_id
    end
  end
end
