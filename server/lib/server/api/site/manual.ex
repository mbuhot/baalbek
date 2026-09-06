defmodule Server.Api.Site.Manual do
  @moduledoc """
  Bridges `Server.Api.Site`'s manual actions to `core`'s exported site functions.

  Calls only `Core`'s domain-level exports — never `Core.Data.Repo` or any
  other `core` internal.
  """

  use Ash.Resource.ManualCreate
  use Ash.Resource.ManualRead
  use Ash.Resource.ManualUpdate
  use Ash.Resource.ManualDestroy

  @doc "Fetches every site from `core`, then lets Ash apply the query's filter/sort/pagination in memory."
  @impl Ash.Resource.ManualRead
  def read(query, _data_layer_query, _opts, _context) do
    with {:ok, core_sites} <- Core.list_sites() do
      Ash.Query.apply_to(query, Enum.map(core_sites, &from_core/1), domain: Server.Api)
    end
  end

  @doc "Creates a site via `Core.create_site/1`."
  @impl Ash.Resource.ManualCreate
  def create(changeset, _opts, _context) do
    attrs = Map.take(changeset.attributes, [:name, :address, :customer_id])

    with {:ok, core_site} <- Core.create_site(attrs) do
      {:ok, from_core(core_site)}
    end
  end

  @doc "Updates a site via `Core.update_site/2`."
  @impl Ash.Resource.ManualUpdate
  def update(changeset, _opts, _context) do
    attrs = Map.take(changeset.attributes, [:name, :address])

    with {:ok, core_site} <- Core.get_site(changeset.data.id),
         {:ok, updated} <- Core.update_site(core_site, attrs) do
      {:ok, from_core(updated)}
    end
  end

  @doc "Destroys a site via `Core.destroy_site/1`."
  @impl Ash.Resource.ManualDestroy
  def destroy(changeset, _opts, _context) do
    with {:ok, core_site} <- Core.get_site(changeset.data.id),
         :ok <- Core.destroy_site(core_site) do
      {:ok, changeset.data}
    end
  end

  defp from_core(core_site) do
    %Server.Api.Site{
      id: core_site.id,
      name: core_site.name,
      address: core_site.address,
      customer_id: core_site.customer_id,
      inserted_at: core_site.inserted_at,
      updated_at: core_site.updated_at
    }
  end
end
