defmodule Billing.Invoicing.Invoice.Changes.CalculateTotal do
  @moduledoc """
  Ash change used by `Billing.Invoicing.Invoice`'s `:issue` action:
  computes `total_amount` as the sum of `quantity * unit_amount` across
  the invoice's `Billing.Invoicing.InvoiceLineItem`s, taken as a snapshot
  at issue time (not a live sum recomputed later — see
  `Billing.Invoicing.Invoice`'s moduledoc).

  Runs in `before_action` so it can read the line items already persisted
  against `changeset.data.id` before this same update commits.
  """

  use Ash.Resource.Change

  require Ash.Query

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
