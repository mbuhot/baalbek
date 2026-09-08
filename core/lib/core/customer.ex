defmodule Core.Customer do
  @moduledoc """
  A customer who requests field-service work and has many `Core.Site`s.
  """

  use Ash.Resource,
    otp_app: :core,
    domain: Core,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]

  json_api do
    type "customer"

    routes do
      base("/customers")

      get(:read)
      index :read
      post(:create)
      patch(:update)
      delete(:destroy)
    end
  end

  postgres do
    table "customers"
    repo Core.Data.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Registers a new customer."
      accept [:name, :email, :phone]
    end

    update :update do
      description "Updates a customer's name, email, or phone."
      accept [:name, :email, :phone]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string,
      allow_nil?: false,
      public?: true,
      description: "The customer's display name."

    attribute :email, :string, public?: true, description: "The customer's contact email address."
    attribute :phone, :string, public?: true, description: "The customer's contact phone number."

    create_timestamp :inserted_at,
      type: :utc_datetime,
      public?: true,
      description: "When this customer was created."

    update_timestamp :updated_at,
      type: :utc_datetime,
      public?: true,
      description: "When this customer was last updated."
  end

  relationships do
    has_many :sites, Core.Site do
      destination_attribute :customer_id
      description "This customer's sites."
    end
  end
end
