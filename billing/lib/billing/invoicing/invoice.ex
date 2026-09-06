defmodule Billing.Invoicing.Invoice do
  @moduledoc """
  An invoice raised from a completed job (PLAN.md's billing component:
  "Invoices raised from completed jobs."). `job_id` deliberately has no
  relationship, foreign key, or compile-time reference to `core.Job` — see
  `Billing.Invoicing`'s moduledoc.

  Lifecycle: `:draft` -> `:issued` -> `:paid`, with `:void` reachable from
  either `:draft` or `:issued`. Each transition is its own action, gated
  by `Billing.Invoicing.Invoice.Validations.CurrentStatus` so an
  out-of-order transition (e.g. marking a still-draft invoice paid) is a
  validation error, not silently accepted. `:issue` additionally requires
  at least one line item
  (`Billing.Invoicing.Invoice.Validations.HasLineItems`) and computes
  `total_amount` from the line items at issue time
  (`Billing.Invoicing.Invoice.Changes.CalculateTotal`) — the total is a
  snapshot taken when the invoice is issued, not a live sum, matching a
  real invoice (line items shouldn't retroactively change an already-sent
  bill).
  """

  use Ash.Resource,
    otp_app: :billing,
    domain: Billing.Invoicing,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "invoices"
    repo Billing.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:job_id, :currency]
    end

    update :issue do
      accept []
      # CurrentStatus/HasLineItems read outside the changeset (a related
      # count, changeset.data.status) and CalculateTotal reads the
      # database mid-change — none of that is expressible as a single SQL
      # expression, so this can't compile into one atomic UPDATE. Same
      # tradeoff as Identity.Accounts.Account's :change_password.
      require_atomic? false

      validate {Billing.Invoicing.Invoice.Validations.CurrentStatus, one_of: [:draft]}
      validate Billing.Invoicing.Invoice.Validations.HasLineItems

      change Billing.Invoicing.Invoice.Changes.CalculateTotal
      change set_attribute(:status, :issued)
      change {Billing.Invoicing.Invoice.Changes.SetTimestamp, attribute: :issued_at}
    end

    update :mark_paid do
      accept []
      require_atomic? false

      validate {Billing.Invoicing.Invoice.Validations.CurrentStatus, one_of: [:issued]}

      change set_attribute(:status, :paid)
      change {Billing.Invoicing.Invoice.Changes.SetTimestamp, attribute: :paid_at}
    end

    update :void do
      accept []
      require_atomic? false

      validate {Billing.Invoicing.Invoice.Validations.CurrentStatus, one_of: [:draft, :issued]}

      change set_attribute(:status, :void)
    end
  end

  attributes do
    uuid_primary_key :id

    # Reference to a `core.Job` by identifier only — see this module's
    # moduledoc and Billing.Invoicing's moduledoc. No relationship, no
    # foreign key, no `core` dependency.
    attribute :job_id, :uuid, allow_nil?: false, public?: true

    attribute :status, :atom do
      constraints one_of: [:draft, :issued, :paid, :void]
      default :draft
      allow_nil? false
      public? true
    end

    attribute :currency, :string do
      default "USD"
      allow_nil? false
      public? true
      constraints max_length: 3
    end

    attribute :total_amount, :decimal do
      default Decimal.new(0)
      allow_nil? false
      public? true
    end

    attribute :issued_at, :utc_datetime, public?: true
    attribute :paid_at, :utc_datetime, public?: true

    timestamps()
  end

  relationships do
    has_many :line_items, Billing.Invoicing.InvoiceLineItem do
      destination_attribute :invoice_id
    end
  end
end
