defmodule Identity.Accounts.Account do
  @moduledoc """
  A technician or dispatcher account, distinguished by its `role` attribute, with registration, authentication, and password-change actions.
  """

  use Ash.Resource,
    otp_app: :identity,
    domain: Identity.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "accounts"
    repo Identity.Repo
  end

  actions do
    defaults [:read, :destroy]

    update :update do
      description "Updates a technician's or dispatcher's name or email."
      accept [:name, :email]
    end

    create :register do
      description "Registers a new technician or dispatcher account, hashing the given password."
      accept [:name, :email, :role]

      argument :password, :string do
        description "Plaintext password to hash into :hashed_password; never stored as given."
        allow_nil? false
        sensitive? true
        constraints min_length: 8
      end

      change Identity.Accounts.Account.Changes.HashPassword
    end

    update :change_password do
      description "Replaces the account's password with a newly hashed one."
      accept []

      # require_atomic?: false — HashPassword hashes via PasswordHasher, not expressible as one SQL UPDATE.
      require_atomic? false

      argument :password, :string do
        description "New plaintext password to hash into :hashed_password."
        allow_nil? false
        sensitive? true
        constraints min_length: 8
      end

      change Identity.Accounts.Account.Changes.HashPassword
    end

    action :authenticate, :struct do
      description "Verifies an email and password against a stored account."
      constraints instance_of: __MODULE__

      argument :email, :string, allow_nil?: false

      argument :password, :string do
        allow_nil? false
        sensitive? true
      end

      run Identity.Accounts.Account.Actions.Authenticate
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string,
      allow_nil?: false,
      public?: true,
      description: "The account holder's display name."

    attribute :email, :string,
      allow_nil?: false,
      public?: true,
      description: "The account holder's unique sign-in email address."

    attribute :role, :atom do
      description "Whether this account belongs to a technician or a dispatcher."
      constraints one_of: [:technician, :dispatcher]
      allow_nil? false
      public? true
    end

    # Never accepted directly; only Changes.HashPassword sets it.
    attribute :hashed_password, :string,
      allow_nil?: false,
      sensitive?: true,
      public?: false,
      description: "PBKDF2-encoded password hash, never accepted as input."

    timestamps()
  end

  identities do
    identity :unique_email, [:email], description: "No two accounts may share the same email."
  end
end
