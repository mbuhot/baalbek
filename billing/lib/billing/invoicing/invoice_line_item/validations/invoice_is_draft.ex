defmodule Billing.Invoicing.InvoiceLineItem.Validations.InvoiceIsDraft do
  @moduledoc """
  Ash validation used by `Billing.Invoicing.InvoiceLineItem`'s `:create`
  action: a line item can only be added to an invoice that is still
  `:draft` — once issued, an invoice's line items (and the total computed
  from them) are frozen.
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    invoice_id = Ash.Changeset.get_attribute(changeset, :invoice_id)

    case invoice_id && Ash.get(Billing.Invoicing.Invoice, invoice_id) do
      {:ok, %Billing.Invoicing.Invoice{status: :draft}} ->
        :ok

      {:ok, %Billing.Invoicing.Invoice{status: other}} ->
        {:error, field: :invoice_id, message: "invoice must be draft (was #{other})"}

      _ ->
        {:error, field: :invoice_id, message: "invoice not found"}
    end
  end
end
