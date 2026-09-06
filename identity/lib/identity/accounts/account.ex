defmodule Identity.Accounts.Account do
  @moduledoc """
  A person who uses the system: a technician or a dispatcher (PLAN.md's
  identity component: "Technicians, dispatchers, auth."). One resource
  with a `role` attribute rather than separate `Technician`/`Dispatcher`
  resources — both kinds of user authenticate the same way and share every
  other attribute; `role` is the only thing that varies, so a shared
  resource avoids duplicating the auth machinery below across two nearly
  identical resources. (Documented default: PLAN.md left this shape
  explicitly open — "whichever you think is cleaner given Ash's resource
  model" — this is the call made for Stage 3.)

  Authentication is real, not a bare unused field: `:register` and
  `:change_password` hash the given plaintext `:password` argument via
  `Identity.Accounts.PasswordHasher` (never storing it), and `:authenticate`
  is a generic action that looks an account up by email and verifies a
  password against the stored hash.
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
      accept [:name, :email]
    end

    create :register do
      accept [:name, :email, :role]

      argument :password, :string do
        allow_nil? false
        sensitive? true
        constraints min_length: 8
      end

      change Identity.Accounts.Account.Changes.HashPassword
    end

    update :change_password do
      accept []
      # Identity.Accounts.Account.Changes.HashPassword calls out to
      # Identity.Accounts.PasswordHasher.hash/1 (not expressible as a SQL
      # expression), so Ash can't compile this update into a single atomic
      # UPDATE statement — same tradeoff as `core`'s non-atomic changes
      # would face; there are none there yet, but this is the first.
      require_atomic? false

      argument :password, :string do
        allow_nil? false
        sensitive? true
        constraints min_length: 8
      end

      change Identity.Accounts.Account.Changes.HashPassword
    end

    action :authenticate, :struct do
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
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :email, :string, allow_nil?: false, public?: true

    attribute :role, :atom do
      constraints one_of: [:technician, :dispatcher]
      allow_nil? false
      public? true
    end

    # Never accepted directly by any action (no `accept :hashed_password`
    # anywhere) and never public — the only way this attribute changes is
    # via Identity.Accounts.Account.Changes.HashPassword, driven by the
    # `:password` argument on :register / :change_password.
    attribute :hashed_password, :string, allow_nil?: false, sensitive?: true, public?: false

    timestamps()
  end

  identities do
    identity :unique_email, [:email]
  end
end
