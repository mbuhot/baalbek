defmodule Server.Api.Customer do
  @moduledoc "JSON:API resource for `core`'s `Core.Customer`, backed by `Core`'s exported customer functions."

  use Ash.Resource,
    domain: Server.Api,
    extensions: [AshJsonApi.Resource]

  json_api do
    type "customer"

    routes do
      base "/customers"

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

      description "Lists or fetches customers via `Core.list_customers/0` and `Core.get_customer/1`."

      manual Server.Api.Customer.Manual
    end

    create :create do
      description "Registers a new customer via `Core.create_customer/1`."
      accept [:name, :email, :phone]
      manual Server.Api.Customer.Manual
    end

    update :update do
      description "Updates a customer's name, email, or phone via `Core.update_customer/2`."
      accept [:name, :email, :phone]
      manual Server.Api.Customer.Manual
    end

    destroy :destroy do
      description "Removes a customer via `Core.destroy_customer/1`."
      manual Server.Api.Customer.Manual
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

    attribute :inserted_at, :utc_datetime,
      writable?: false,
      public?: true,
      description: "When this customer was created."

    attribute :updated_at, :utc_datetime,
      writable?: false,
      public?: true,
      description: "When this customer was last updated."
  end
end
