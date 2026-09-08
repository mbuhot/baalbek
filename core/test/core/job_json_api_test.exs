defmodule Core.JobJsonApiTest do
  @moduledoc "Exercises `/jobs` end to end against the real `core` schema/role."

  use Core.JsonApiCase, async: true

  defp create_site! do
    customer = Core.create_customer!(%{name: "Acme Facilities", email: "ops@acme.test"})
    Core.create_site!(%{name: "Warehouse 1", address: "1 Dock Rd", customer_id: customer.id})
  end

  describe "POST /jobs" do
    test "requests a new job at a site, defaulting to :requested" do
      site = create_site!()

      body = %{
        "data" => %{
          "type" => "job",
          "attributes" => %{"title" => "Fix conveyor", "site_id" => site.id}
        }
      }

      {status, doc} = request(:post, "/jobs", body)

      assert status == 201
      assert %{"data" => data} = doc
      assert data["attributes"]["title"] == "Fix conveyor"
      assert data["attributes"]["status"] == "requested"
      assert {:ok, %Core.Job{status: :requested}} = Core.get_job(data["id"])
    end
  end

  describe "GET /jobs and GET /jobs/:id" do
    test "lists then fetches a job" do
      site = create_site!()
      job = Core.create_job!(%{title: "Fix conveyor", site_id: site.id})

      {status, doc} = request(:get, "/jobs")
      assert status == 200
      assert %{"data" => data} = doc
      assert Enum.any?(data, &(&1["id"] == job.id))

      {status, doc} = request(:get, "/jobs/#{job.id}")
      assert status == 200
      assert %{"data" => %{"id" => id}} = doc
      assert id == job.id
    end
  end

  describe "PATCH /jobs/:id" do
    test "transitions a job's status via Core.update_job/2" do
      site = create_site!()
      job = Core.create_job!(%{title: "Fix conveyor", site_id: site.id})

      body = %{
        "data" => %{"type" => "job", "id" => job.id, "attributes" => %{"status" => "scheduled"}}
      }

      {status, doc} = request(:patch, "/jobs/#{job.id}", body)

      assert status == 200
      assert %{"data" => %{"attributes" => %{"status" => "scheduled"}}} = doc
      assert {:ok, %Core.Job{status: :scheduled}} = Core.get_job(job.id)
    end
  end
end
