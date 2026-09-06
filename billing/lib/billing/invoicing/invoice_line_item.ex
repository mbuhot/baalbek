defmodule Billing.Invoicing.InvoiceLineItem do
  @moduledoc """
  A single charge line on a `Billing.Invoicing.Invoice` — a description,
  quantity, and per-unit amount. `amount = quantity * unit_amount`, summed
  across an invoice's line items into `total_amount` when the invoice is
  issued (`Billing.Invoicing.Invoice.Changes.CalculateTotal`).

  Line items can only be added while the parent invoice is still `:draft`
  (`Billing.Invoicing.InvoiceLineItem.Validations.InvoiceIsDraft`) — once
  issued, an invoice's line items are frozen along with its computed
  total.
  """

  use Ash.Resource,
    otp_app: :billing,
    domain: Billing.Invoicing,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "invoice_line_items"
    repo Billing.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:invoice_id, :description, :quantity, :unit_amount]

      validate Billing.Invoicing.InvoiceLineItem.Validations.InvoiceIsDraft
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :description, :string, allow_nil?: false, public?: true

    attribute :quantity, :integer do
      default 1
      allow_nil? false
      public? true
      constraints min: 1
    end

    attribute :unit_amount, :decimal, allow_nil?: false, public?: true

    timestamps()
  end

  relationships do
    belongs_to :invoice, Billing.Invoicing.Invoice do
      allow_nil? false
      attribute_writable? true
    end
  end
end
