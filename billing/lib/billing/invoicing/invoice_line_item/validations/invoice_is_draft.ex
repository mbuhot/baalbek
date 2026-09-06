defmodule Billing.Invoicing.InvoiceLineItem.Validations.InvoiceIsDraft do
  @moduledoc """
  Ash validation rejecting `Billing.Invoicing.InvoiceLineItem`'s `:create` action unless the parent invoice is still `:draft`.
  """

  use Ash.Resource.Validation

  @doc "Fails unless the line item's invoice is currently :draft."
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
