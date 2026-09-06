defmodule Billing.Invoicing.InvoiceLineItem do
  @moduledoc """
  A single charge line on a `Billing.Invoicing.Invoice`, addable only while that invoice is still `:draft`.
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
      description "Adds a charge line to a draft invoice."
      accept [:invoice_id, :description, :quantity, :unit_amount]

      validate Billing.Invoicing.InvoiceLineItem.Validations.InvoiceIsDraft
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :description, :string,
      allow_nil?: false,
      public?: true,
      description: "What the charge is for, as it appears on the invoice."

    attribute :quantity, :integer do
      description "How many units of this charge are being billed."
      default 1
      allow_nil? false
      public? true
      constraints min: 1
    end

    attribute :unit_amount, :decimal,
      allow_nil?: false,
      public?: true,
      description:
        "Price per unit; the line's contribution to the invoice total is quantity * unit_amount."

    timestamps()
  end

  relationships do
    belongs_to :invoice, Billing.Invoicing.Invoice do
      description "The invoice this line item belongs to."
      allow_nil? false
      attribute_writable? true
    end
  end
end
