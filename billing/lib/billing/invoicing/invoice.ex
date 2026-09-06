defmodule Billing.Invoicing.Invoice do
  @moduledoc """
  An invoice raised from a completed job, referenced by `job_id` alone.

  Its status moves only `:draft` -> `:issued` -> `:paid`, with `:void`
  reachable from either `:draft` or `:issued`. Each transition is a
  separate action that rejects an out-of-order call. Issuing also
  requires at least one line item and freezes `total_amount` as a
  snapshot at that moment.
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
      description "Drafts a new invoice for a completed job."
      accept [:job_id, :currency]
    end

    update :issue do
      description "Issues a draft invoice, freezing its total and requiring at least one line item."
      accept []

      # require_atomic?: false — CalculateTotal reads the database mid-change, not one SQL UPDATE.
      require_atomic? false

      validate {Billing.Invoicing.Invoice.Validations.CurrentStatus, one_of: [:draft]}
      validate Billing.Invoicing.Invoice.Validations.HasLineItems

      change Billing.Invoicing.Invoice.Changes.CalculateTotal
      change set_attribute(:status, :issued)
      change {Billing.Invoicing.Invoice.Changes.SetTimestamp, attribute: :issued_at}
    end

    update :mark_paid do
      description "Marks an issued invoice as paid."
      accept []
      require_atomic? false

      validate {Billing.Invoicing.Invoice.Validations.CurrentStatus, one_of: [:issued]}

      change set_attribute(:status, :paid)
      change {Billing.Invoicing.Invoice.Changes.SetTimestamp, attribute: :paid_at}
    end

    update :void do
      description "Cancels a draft or issued invoice."
      accept []
      require_atomic? false

      validate {Billing.Invoicing.Invoice.Validations.CurrentStatus, one_of: [:draft, :issued]}

      change set_attribute(:status, :void)
    end
  end

  attributes do
    uuid_primary_key :id

    # References a `core.Job` by id only — no relationship, foreign key, or `core` dependency.
    attribute :job_id, :uuid,
      allow_nil?: false,
      public?: true,
      description: "Id of the completed job this invoice bills for."

    attribute :status, :atom do
      description "Where this invoice sits in its draft -> issued -> paid lifecycle (or void)."
      constraints one_of: [:draft, :issued, :paid, :void]
      default :draft
      allow_nil? false
      public? true
    end

    attribute :currency, :string do
      description "ISO 4217 currency code for total_amount and every line item's unit_amount."
      default "USD"
      allow_nil? false
      public? true
      constraints max_length: 3
    end

    attribute :total_amount, :decimal do
      description "The invoice total, computed once from its line items when issued."
      default Decimal.new(0)
      allow_nil? false
      public? true
    end

    attribute :issued_at, :utc_datetime,
      public?: true,
      description: "When the invoice moved to :issued."

    attribute :paid_at, :utc_datetime,
      public?: true,
      description: "When the invoice moved to :paid."

    timestamps()
  end

  relationships do
    has_many :line_items, Billing.Invoicing.InvoiceLineItem do
      description "The charge lines that make up this invoice's total."
      destination_attribute :invoice_id
    end
  end
end
