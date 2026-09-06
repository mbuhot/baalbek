defmodule Server.Api.Job.Manual do
  @moduledoc """
  Bridges `Server.Api.Job`'s manual actions to `core`'s exported job functions.

  Calls only `Core`'s domain-level exports — never `Core.Data.Repo` or any
  other `core` internal.
  """

  use Ash.Resource.ManualCreate
  use Ash.Resource.ManualRead
  use Ash.Resource.ManualUpdate
  use Ash.Resource.ManualDestroy

  @doc "Fetches every job from `core`, then lets Ash apply the query's filter/sort/pagination in memory."
  @impl Ash.Resource.ManualRead
  def read(query, _data_layer_query, _opts, _context) do
    with {:ok, core_jobs} <- Core.list_jobs() do
      Ash.Query.apply_to(query, Enum.map(core_jobs, &from_core/1), domain: Server.Api)
    end
  end

  @doc "Creates a job via `Core.create_job/1`."
  @impl Ash.Resource.ManualCreate
  def create(changeset, _opts, _context) do
    attrs =
      Map.take(changeset.attributes, [:title, :description, :status, :scheduled_at, :site_id])

    with {:ok, core_job} <- Core.create_job(attrs) do
      {:ok, from_core(core_job)}
    end
  end

  @doc "Updates a job via `Core.update_job/2`."
  @impl Ash.Resource.ManualUpdate
  def update(changeset, _opts, _context) do
    attrs = Map.take(changeset.attributes, [:title, :description, :status, :scheduled_at])

    with {:ok, core_job} <- Core.get_job(changeset.data.id),
         {:ok, updated} <- Core.update_job(core_job, attrs) do
      {:ok, from_core(updated)}
    end
  end

  @doc "Destroys a job via `Core.destroy_job/1`."
  @impl Ash.Resource.ManualDestroy
  def destroy(changeset, _opts, _context) do
    with {:ok, core_job} <- Core.get_job(changeset.data.id),
         :ok <- Core.destroy_job(core_job) do
      {:ok, changeset.data}
    end
  end

  defp from_core(core_job) do
    %Server.Api.Job{
      id: core_job.id,
      title: core_job.title,
      description: core_job.description,
      status: core_job.status,
      scheduled_at: core_job.scheduled_at,
      site_id: core_job.site_id,
      inserted_at: core_job.inserted_at,
      updated_at: core_job.updated_at
    }
  end
end
