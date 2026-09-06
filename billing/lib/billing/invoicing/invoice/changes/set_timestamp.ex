defmodule Billing.Invoicing.Invoice.Changes.SetTimestamp do
  @moduledoc """
  Ash change that force-sets a given attribute to `DateTime.utc_now/0` —
  used by `Billing.Invoicing.Invoice`'s `:issue` (`:issued_at`) and
  `:mark_paid` (`:paid_at`) actions, each a genuine lifecycle event
  timestamp rather than the record's generic `updated_at`.
  """

  use Ash.Resource.Change

  @impl true
  def init(opts) do
    if Keyword.has_key?(opts, :attribute) do
      {:ok, opts}
    else
      {:error, "SetTimestamp requires an :attribute option"}
    end
  end

  @impl true
  def change(changeset, opts, _context) do
    attribute = Keyword.fetch!(opts, :attribute)
    Ash.Changeset.force_change_attribute(changeset, attribute, DateTime.utc_now())
  end
end
