defmodule Billing.Invoicing.Invoice.Validations.HasLineItems do
  @moduledoc """
  Ash validation rejecting `Billing.Invoicing.Invoice`'s `:issue` action when the invoice has no line items.
  """

  use Ash.Resource.Validation

  require Ash.Query

  @doc "Fails unless the invoice has at least one line item."
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
