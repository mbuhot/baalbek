defmodule Billing.Invoicing do
  @moduledoc """
  The `billing` domain: invoices and their line items, raised from completed jobs referenced by id only.
  """

  use Ash.Domain,
    otp_app: :billing,
    extensions: [AshBoundary]

  boundary do
    deps [Billing.Repo]
  end

  resources do
    resource Billing.Invoicing.Invoice do
      define :draft_invoice, action: :create, args: [:job_id]
      define :get_invoice, action: :read, get_by: [:id]
      define :list_invoices, action: :read
      define :issue_invoice, action: :issue
      define :mark_invoice_paid, action: :mark_paid
      define :void_invoice, action: :void
    end

    resource Billing.Invoicing.InvoiceLineItem do
      define :add_line_item,
        action: :create,
        args: [:invoice_id, :description, :quantity, :unit_amount]
    end
  end
end
