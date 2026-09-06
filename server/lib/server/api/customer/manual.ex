defmodule Server.Api.Customer.Manual do
  @moduledoc """
  Bridges `Server.Api.Customer`'s manual actions to `core`'s exported customer functions.

  Every function below calls only `Core`'s domain-level exports
  (`Core.list_customers/0`, `Core.get_customer/1`, etc.) — never
  `Core.Data.Repo` or any other `core` internal.
  """

  use Ash.Resource.ManualCreate
  use Ash.Resource.ManualRead
  use Ash.Resource.ManualUpdate
  use Ash.Resource.ManualDestroy

  @doc "Fetches every customer from `core`, then lets Ash apply the query's filter/sort/pagination in memory."
  @impl Ash.Resource.ManualRead
  def read(query, _data_layer_query, _opts, _context) do
    with {:ok, core_customers} <- Core.list_customers() do
      Ash.Query.apply_to(query, Enum.map(core_customers, &from_core/1), domain: Server.Api)
    end
  end

  @doc "Creates a customer via `Core.create_customer/1`."
  @impl Ash.Resource.ManualCreate
  def create(changeset, _opts, _context) do
    attrs = Map.take(changeset.attributes, [:name, :email, :phone])

    with {:ok, core_customer} <- Core.create_customer(attrs) do
      {:ok, from_core(core_customer)}
    end
  end

  @doc "Updates a customer via `Core.update_customer/2`."
  @impl Ash.Resource.ManualUpdate
  def update(changeset, _opts, _context) do
    attrs = Map.take(changeset.attributes, [:name, :email, :phone])

    with {:ok, core_customer} <- Core.get_customer(changeset.data.id),
         {:ok, updated} <- Core.update_customer(core_customer, attrs) do
      {:ok, from_core(updated)}
    end
  end

  @doc "Destroys a customer via `Core.destroy_customer/1`."
  @impl Ash.Resource.ManualDestroy
  def destroy(changeset, _opts, _context) do
    with {:ok, core_customer} <- Core.get_customer(changeset.data.id),
         :ok <- Core.destroy_customer(core_customer) do
      {:ok, changeset.data}
    end
  end

  # `core_customer` is a `%Core.Customer{}` struct, referenced here only via
  # plain field access (never `alias`ed or pattern-matched by name), since
  # `Core.Customer` isn't itself a call target `server` needs boundary
  # clearance for — only `Core`'s domain-level functions are.
  defp from_core(core_customer) do
    %Server.Api.Customer{
      id: core_customer.id,
      name: core_customer.name,
      email: core_customer.email,
      phone: core_customer.phone,
      inserted_at: core_customer.inserted_at,
      updated_at: core_customer.updated_at
    }
  end
end
