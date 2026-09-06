defmodule Billing.Invoicing.Invoice.Validations.CurrentStatus do
  @moduledoc """
  Ash validation enforcing an invoice's lifecycle: the action-in-progress
  is only allowed when `changeset.data.status` (the status *before* this
  update, not whatever the changeset would set it to) is one of the
  statuses given in `:one_of`. Used by `Billing.Invoicing.Invoice`'s
  `:issue` (must be `:draft`), `:mark_paid` (must be `:issued`), and
  `:void` (must be `:draft` or `:issued`) actions, so an out-of-order
  transition (double-issue, paying a draft, voiding an already-paid
  invoice) is a real validation error, not silently accepted.
  """

  use Ash.Resource.Validation

  @impl true
  def init(opts) do
    if Keyword.has_key?(opts, :one_of) do
      {:ok, opts}
    else
      {:error, "CurrentStatus requires a :one_of option"}
    end
  end

  @impl true
  def validate(changeset, opts, _context) do
    allowed = Keyword.fetch!(opts, :one_of)
    current = changeset.data.status

    if current in allowed do
      :ok
    else
      {:error,
       field: :status,
       message: "must currently be #{inspect(allowed)} for this action (was #{inspect(current)})"}
    end
  end
end
