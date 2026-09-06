defmodule Billing.Invoicing do
  @moduledoc """
  The billing domain: invoices raised from completed jobs (PLAN.md's
  Component inventory: "Invoices raised from completed jobs.").

  `job_id` on `Billing.Invoicing.Invoice` is a bare `:uuid` — a reference
  to a job owned by `core`'s schema *by identifier only*. There is no
  foreign-key constraint across schemas and no compile-time/Mix path
  dependency on `core` (seed.md §5: schema merging/entity reconciliation
  across components is deliberately out of scope for the structure;
  PLAN.md's "cross-schema queries possible when genuinely needed, not
  routine" — a routine FK-style join here is exactly what NOT to do).

  Uses `ash_boundary` (PLAN.md's "Boundary enforcement, in-app and
  cross-app" section) instead of a hand-rolled `use Boundary` on a plain
  module — see `Identity.Accounts`'s moduledoc for the general rationale,
  which applies identically here. `Billing.Invoicing.Invoice` and
  `Billing.Invoicing.InvoiceLineItem` each get at least one domain-level
  `define`, so both are exported; the change/validation modules backing
  them stay internal.
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
