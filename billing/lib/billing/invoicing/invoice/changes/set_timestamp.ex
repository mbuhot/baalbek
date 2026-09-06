defmodule Billing.Invoicing.Invoice.Changes.SetTimestamp do
  @moduledoc """
  Ash change that force-sets a given `:attribute` to the current UTC time.
  """

  use Ash.Resource.Change

  @doc "Validates that an :attribute option was given."
  @impl true
  def init(opts) do
    if Keyword.has_key?(opts, :attribute) do
      {:ok, opts}
    else
      {:error, "SetTimestamp requires an :attribute option"}
    end
  end

  @doc "Force-sets the configured attribute to DateTime.utc_now/0."
  @impl true
  def change(changeset, opts, _context) do
    attribute = Keyword.fetch!(opts, :attribute)
    Ash.Changeset.force_change_attribute(changeset, attribute, DateTime.utc_now())
  end
end
