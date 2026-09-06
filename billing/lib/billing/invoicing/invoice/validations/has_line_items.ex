defmodule Billing.Invoicing.Invoice.Validations.HasLineItems do
  @moduledoc """
  Ash validation used by `Billing.Invoicing.Invoice`'s `:issue` action:
  rejects issuing an invoice that has no
  `Billing.Invoicing.InvoiceLineItem`s yet — an invoice with a $0 total
  and no line items would be a real bug, not a legitimate empty invoice.
  """

  use Ash.Resource.Validation

  require Ash.Query

  @impl true
  def validate(changeset, _opts, _context) do
    count =
      Billing.Invoicing.InvoiceLineItem
      |> Ash.Query.filter(invoice_id == ^changeset.data.id)
      |> Ash.count!()

    if count > 0 do
      :ok
    else
      {:error, "cannot issue an invoice with no line items"}
    end
  end
end
