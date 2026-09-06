defmodule Server.Api.WorkOrder.Manual do
  @moduledoc """
  Bridges `Server.Api.WorkOrder`'s manual actions to `core`'s exported work-order functions.

  Calls only `Core`'s domain-level exports — never `Core.Data.Repo` or any
  other `core` internal.
  """

  use Ash.Resource.ManualCreate
  use Ash.Resource.ManualRead
  use Ash.Resource.ManualUpdate
  use Ash.Resource.ManualDestroy

  @doc "Fetches every work order from `core`, then lets Ash apply the query's filter/sort/pagination in memory."
  @impl Ash.Resource.ManualRead
  def read(query, _data_layer_query, _opts, _context) do
    with {:ok, core_work_orders} <- Core.list_work_orders() do
      Ash.Query.apply_to(query, Enum.map(core_work_orders, &from_core/1), domain: Server.Api)
    end
  end

  @doc "Creates a work order via `Core.create_work_order/1`."
  @impl Ash.Resource.ManualCreate
  def create(changeset, _opts, _context) do
    attrs = Map.take(changeset.attributes, [:summary, :status, :completed_at, :job_id])

    with {:ok, core_work_order} <- Core.create_work_order(attrs) do
      {:ok, from_core(core_work_order)}
    end
  end

  @doc "Updates a work order via `Core.update_work_order/2`."
  @impl Ash.Resource.ManualUpdate
  def update(changeset, _opts, _context) do
    attrs = Map.take(changeset.attributes, [:summary, :status, :completed_at])

    with {:ok, core_work_order} <- Core.get_work_order(changeset.data.id),
         {:ok, updated} <- Core.update_work_order(core_work_order, attrs) do
      {:ok, from_core(updated)}
    end
  end

  @doc "Destroys a work order via `Core.destroy_work_order/1`."
  @impl Ash.Resource.ManualDestroy
  def destroy(changeset, _opts, _context) do
    with {:ok, core_work_order} <- Core.get_work_order(changeset.data.id),
         :ok <- Core.destroy_work_order(core_work_order) do
      {:ok, changeset.data}
    end
  end

  defp from_core(core_work_order) do
    %Server.Api.WorkOrder{
      id: core_work_order.id,
      summary: core_work_order.summary,
      status: core_work_order.status,
      completed_at: core_work_order.completed_at,
      job_id: core_work_order.job_id,
      inserted_at: core_work_order.inserted_at,
      updated_at: core_work_order.updated_at
    }
  end
end
