defmodule Server.Api.Site do
  @moduledoc "JSON:API resource for `core`'s `Core.Site`, backed by `Core`'s exported site functions."

  use Ash.Resource,
    domain: Server.Api,
    extensions: [AshJsonApi.Resource]

  json_api do
    type "site"

    routes do
      base "/sites"

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
      description "Lists or fetches sites via `Core.list_sites/0` and `Core.get_site/1`."
      manual Server.Api.Site.Manual
    end

    create :create do
      description "Registers a new site for a customer via `Core.create_site/1`."
      accept [:name, :address, :customer_id]
      manual Server.Api.Site.Manual
    end

    update :update do
      description "Updates a site's name or address via `Core.update_site/2`."
      accept [:name, :address]
      manual Server.Api.Site.Manual
    end

    destroy :destroy do
      description "Removes a site via `Core.destroy_site/1`."
      manual Server.Api.Site.Manual
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string,
      allow_nil?: false,
      public?: true,
      description: "The site's display name."

    attribute :address, :string, public?: true, description: "The site's street address."

    attribute :customer_id, :uuid,
      allow_nil?: false,
      public?: true,
      description: "The id of the customer this site belongs to."

    attribute :inserted_at, :utc_datetime,
      writable?: false,
      public?: true,
      description: "When this site was created."

    attribute :updated_at, :utc_datetime,
      writable?: false,
      public?: true,
      description: "When this site was last updated."
  end
end
