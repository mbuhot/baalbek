defmodule Core.Spec.JobDispatchSteps do
  @moduledoc "Steps for spec/features/job_dispatch.feature, driving the real `Core` code interface."

  use Cucumber.StepDefinition
  import ExUnit.Assertions

  step "a customer {string}", %{args: [name]} = context do
    {:ok, customer} = Core.create_customer(%{name: name, email: "ops@acme.test"})
    Map.put(context, :customer, customer)
  end

  step "the customer has a site {string}", %{args: [name]} = context do
    {:ok, site} =
      Core.create_site(%{name: name, address: "1 Dock Rd", customer_id: context.customer.id})

    Map.put(context, :sites, Map.put(context[:sites] || %{}, name, site))
  end

  step "a job {string} is requested at {string}", %{args: [title, site_name]} = context do
    site = Map.fetch!(context.sites, site_name)
    {:ok, job} = Core.create_job(%{title: title, site_id: site.id})
    Map.put(context, :job, job)
  end

  step "the job is moved to {string}", %{args: [status]} = context do
    record(context, Core.update_job(context.job, %{status: String.to_atom(status)}))
  end

  step "the following work orders are opened against the job:", context do
    for row <- context.datatable.maps do
      {:ok, _} = Core.create_work_order(%{summary: row["summary"], job_id: context.job.id})
    end

    context
  end

  step "a work order {string} is opened against no job", %{args: [summary]} = context do
    record(context, Core.create_work_order(%{summary: summary}))
  end

  step "the change is rejected", context do
    assert {:error, %Ash.Error.Invalid{}} = context.last_result
    context
  end

  step "the job status is {string}", %{args: [status]} = context do
    assert context.job.status == String.to_existing_atom(status)
    context
  end

  step "the job belongs to the site {string}", %{args: [site_name]} = context do
    assert context.job.site_id == Map.fetch!(context.sites, site_name).id
    context
  end

  step "the job has {int} work orders", %{args: [count]} = context do
    loaded = Ash.load!(context.job, :work_orders)
    assert length(loaded.work_orders) == count
    Map.put(context, :work_orders, loaded.work_orders)
  end

  step "every work order status is {string}", %{args: [status]} = context do
    expected = String.to_existing_atom(status)
    assert Enum.all?(context.work_orders, &(&1.status == expected))
    context
  end

  # Keeps :job pointing at the last accepted state, so a rejected change
  # leaves the assertions reading the job as it stood before it.
  defp record(context, result) do
    context = Map.put(context, :last_result, result)

    case result do
      {:ok, %Core.Job{} = job} -> Map.put(context, :job, job)
      _ -> context
    end
  end
end
