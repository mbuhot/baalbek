defmodule ServerWeb.JobJsonApiTest do
  @moduledoc "Exercises `/api/json/core/jobs` end to end against the real `core` schema/role."

  use ServerWeb.ConnCase, async: true

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Core.Data.Repo)
  end

  defp create_site! do
    customer = Core.create_customer!(%{name: "Acme Facilities", email: "ops@acme.test"})
    Core.create_site!(%{name: "Warehouse 1", address: "1 Dock Rd", customer_id: customer.id})
  end

  describe "POST /jobs" do
    test "requests a new job at a site, defaulting to :requested", %{conn: conn} do
      site = create_site!()

      body = %{
        "data" => %{
          "type" => "job",
          "attributes" => %{"title" => "Fix conveyor", "site_id" => site.id}
        }
      }

      conn = post(conn, "/api/json/core/jobs", body)

      assert %{"data" => data} = json_response(conn, 201)
      assert data["attributes"]["title"] == "Fix conveyor"
      assert data["attributes"]["status"] == "requested"
      assert {:ok, %Core.Job{status: :requested}} = Core.get_job(data["id"])
    end
  end

  describe "GET /jobs and GET /jobs/:id" do
    test "lists then fetches a job", %{conn: conn} do
      site = create_site!()
      job = Core.create_job!(%{title: "Fix conveyor", site_id: site.id})

      list_conn = get(conn, "/api/json/core/jobs")
      assert %{"data" => data} = json_response(list_conn, 200)
      assert Enum.any?(data, &(&1["id"] == job.id))

      get_conn = get(conn, "/api/json/core/jobs/#{job.id}")
      assert %{"data" => %{"id" => id}} = json_response(get_conn, 200)
      assert id == job.id
    end
  end

  describe "PATCH /jobs/:id" do
    test "transitions a job's status via Core.update_job/2", %{conn: conn} do
      site = create_site!()
      job = Core.create_job!(%{title: "Fix conveyor", site_id: site.id})

      body = %{
        "data" => %{"type" => "job", "id" => job.id, "attributes" => %{"status" => "scheduled"}}
      }

      conn = patch(conn, "/api/json/core/jobs/#{job.id}", body)

      assert %{"data" => %{"attributes" => %{"status" => "scheduled"}}} = json_response(conn, 200)
      assert {:ok, %Core.Job{status: :scheduled}} = Core.get_job(job.id)
    end
  end
end
