defmodule Billing.Invoicing.Invoice.Changes.CalculateTotal do
  @moduledoc """
  Ash change that sets `total_amount` to the sum of `quantity * unit_amount` across the invoice's line items.
  """

  use Ash.Resource.Change

  require Ash.Query

  @doc "Sums the invoice's line items and force-sets total_amount to the result."
  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      total =
        Billing.Invoicing.InvoiceLineItem
        |> Ash.Query.filter(invoice_id == ^changeset.data.id)
        |> Ash.read!()
        |> Enum.reduce(Decimal.new(0), fn line_item, acc ->
          line_total = Decimal.mult(line_item.unit_amount, Decimal.new(line_item.quantity))
          Decimal.add(acc, line_total)
        end)

      Ash.Changeset.force_change_attribute(changeset, :total_amount, total)
    end)
  end
end
