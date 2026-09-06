defmodule Core.Site do
  @moduledoc """
  A physical location belonging to a `Core.Customer`, where `Core.Job`s happen.
  """

  use Ash.Resource,
    otp_app: :core,
    domain: Core,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "sites"
    repo Core.Data.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Registers a new site for a customer."
      accept [:name, :address, :customer_id]
    end

    update :update do
      description "Updates a site's name or address."
      accept [:name, :address]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string,
      allow_nil?: false,
      public?: true,
      description: "The site's display name."

    attribute :address, :string, public?: true, description: "The site's street address."
    timestamps()
  end

  relationships do
    belongs_to :customer, Core.Customer do
      allow_nil? false
      attribute_writable? true
      description "The customer this site belongs to."
    end

    has_many :jobs, Core.Job do
      destination_attribute :site_id
      description "This site's jobs."
    end
  end
end
