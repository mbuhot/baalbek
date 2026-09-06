defmodule Billing.Invoicing.Invoice.Validations.CurrentStatus do
  @moduledoc """
  Ash validation rejecting an update unless the invoice's current status is one of the given `:one_of` statuses.
  """

  use Ash.Resource.Validation

  @doc "Validates that a :one_of option was given."
  @impl true
  def init(opts) do
    if Keyword.has_key?(opts, :one_of) do
      {:ok, opts}
    else
      {:error, "CurrentStatus requires a :one_of option"}
    end
  end

  @doc "Checks the invoice's pre-update status against the allowed :one_of list."
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
