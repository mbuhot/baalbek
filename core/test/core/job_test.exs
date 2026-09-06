defmodule Core.JobTest do
  @moduledoc """
  Exercises `Core.Job`'s status lifecycle against the real `core`
  schema/role — per seed.md §7's governing principle, this suite must be a
  real proof, runnable alone, never stubbed against a fake data layer.
  """

  use ExUnit.Case, async: true

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Core.Data.Repo)
  end

  defp create_site! do
    customer =
      Core.Customer
      |> Ash.Changeset.for_create(:create, %{name: "Acme Facilities", email: "ops@acme.test"})
      |> Ash.create!()

    Core.Site
    |> Ash.Changeset.for_create(:create, %{
      name: "Warehouse 1",
      address: "1 Dock Rd",
      customer_id: customer.id
    })
    |> Ash.create!()
  end

  test "defaults to :requested and accepts a valid transition" do
    site = create_site!()

    job =
      Core.Job
      |> Ash.Changeset.for_create(:create, %{title: "Fix conveyor", site_id: site.id})
      |> Ash.create!()

    assert job.status == :requested

    scheduled =
      job
      |> Ash.Changeset.for_update(:update, %{status: :scheduled})
      |> Ash.update!()

    assert scheduled.status == :scheduled
  end

  test "rejects a status outside the declared set" do
    site = create_site!()

    assert {:error, %Ash.Error.Invalid{}} =
             Core.Job
             |> Ash.Changeset.for_create(:create, %{
               title: "Bad status",
               site_id: site.id,
               status: :not_a_real_status
             })
             |> Ash.create()
  end
end
