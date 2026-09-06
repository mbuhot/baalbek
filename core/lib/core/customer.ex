defmodule Core.Customer do
  @moduledoc """
  A customer who requests field-service work. Has many `Core.Site`s.
  """

  use Ash.Resource,
    otp_app: :core,
    domain: Core.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "customers"
    repo Core.Data.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :email, :phone]
    end

    update :update do
      accept [:name, :email, :phone]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :email, :string, public?: true
    attribute :phone, :string, public?: true
    timestamps()
  end

  relationships do
    has_many :sites, Core.Site do
      destination_attribute :customer_id
    end
  end
end
