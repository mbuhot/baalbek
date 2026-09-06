defmodule Core.DomainTest do
  @moduledoc """
  Exercises the relationships spanning `core`'s resources — customer, site,
  job, work order — against the real `core` schema/role. Per seed.md §7's
  governing principle, this suite must be a real proof, runnable alone,
  never stubbed against a fake data layer.
  """

  use ExUnit.Case, async: true

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Core.Data.Repo)
  end

  defp create_customer!(attrs \\ %{}) do
    Core.Customer
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(%{name: "Acme Facilities", email: "ops@acme.test", phone: "555-0100"}, attrs)
    )
    |> Ash.create!()
  end

  defp create_site!(customer, attrs \\ %{}) do
    Core.Site
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(
        %{name: "Warehouse 1", address: "1 Dock Rd", customer_id: customer.id},
        attrs
      )
    )
    |> Ash.create!()
  end

  defp create_job!(site, attrs \\ %{}) do
    Core.Job
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(%{title: "Fix conveyor", site_id: site.id}, attrs)
    )
    |> Ash.create!()
  end

  defp create_work_order!(job, attrs \\ %{}) do
    Core.WorkOrder
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(%{summary: "Initial visit", job_id: job.id}, attrs)
    )
    |> Ash.create!()
  end

  test "customer -> site -> job -> work_order, and loading them back" do
    customer = create_customer!()
    site = create_site!(customer)
    job = create_job!(site)
    work_order = create_work_order!(job)

    assert site.customer_id == customer.id
    assert job.site_id == site.id
    assert work_order.job_id == job.id

    loaded_customer = Ash.load!(customer, :sites)
    assert [%Core.Site{id: site_id}] = loaded_customer.sites
    assert site_id == site.id

    loaded_site = Ash.load!(site, [:customer, :jobs])
    assert loaded_site.customer.id == customer.id
    assert [%Core.Job{id: job_id}] = loaded_site.jobs
    assert job_id == job.id

    loaded_job = Ash.load!(job, [:site, :work_orders])
    assert loaded_job.site.id == site.id
    assert [%Core.WorkOrder{id: wo_id}] = loaded_job.work_orders
    assert wo_id == work_order.id

    loaded_work_order = Ash.load!(work_order, :job)
    assert loaded_work_order.job.id == job.id
  end

  test "a job can have more than one work order" do
    customer = create_customer!()
    site = create_site!(customer)
    job = create_job!(site)

    create_work_order!(job, %{summary: "Initial visit"})
    create_work_order!(job, %{summary: "Follow-up visit"})

    loaded_job = Ash.load!(job, :work_orders)
    assert length(loaded_job.work_orders) == 2
  end
end
