defmodule ServerWeb.WorkOrderJsonApiTest do
  @moduledoc "Exercises `/api/json/core/work_orders` end to end against the real `core` schema/role."

  use ServerWeb.ConnCase, async: true

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Core.Data.Repo)
  end

  defp create_job! do
    customer = Core.create_customer!(%{name: "Acme Facilities", email: "ops@acme.test"})

    site =
      Core.create_site!(%{name: "Warehouse 1", address: "1 Dock Rd", customer_id: customer.id})

    Core.create_job!(%{title: "Fix conveyor", site_id: site.id})
  end

  describe "POST /work_orders" do
    test "opens a new work order against a job", %{conn: conn} do
      job = create_job!()

      body = %{
        "data" => %{
          "type" => "work_order",
          "attributes" => %{"summary" => "Initial visit", "job_id" => job.id}
        }
      }

      conn = post(conn, "/api/json/core/work_orders", body)

      assert %{"data" => data} = json_response(conn, 201)
      assert data["attributes"]["summary"] == "Initial visit"
      assert data["attributes"]["status"] == "open"
      assert {:ok, %Core.WorkOrder{}} = Core.get_work_order(data["id"])
    end
  end

  describe "GET /work_orders and GET /work_orders/:id" do
    test "lists then fetches a work order", %{conn: conn} do
      job = create_job!()
      work_order = Core.create_work_order!(%{summary: "Initial visit", job_id: job.id})

      list_conn = get(conn, "/api/json/core/work_orders")
      assert %{"data" => data} = json_response(list_conn, 200)
      assert Enum.any?(data, &(&1["id"] == work_order.id))

      get_conn = get(conn, "/api/json/core/work_orders/#{work_order.id}")
      assert %{"data" => %{"id" => id}} = json_response(get_conn, 200)
      assert id == work_order.id
    end
  end

  describe "PATCH /work_orders/:id" do
    test "marks a work order completed via Core.update_work_order/2", %{conn: conn} do
      job = create_job!()
      work_order = Core.create_work_order!(%{summary: "Initial visit", job_id: job.id})

      body = %{
        "data" => %{
          "type" => "work_order",
          "id" => work_order.id,
          "attributes" => %{"status" => "completed"}
        }
      }

      conn = patch(conn, "/api/json/core/work_orders/#{work_order.id}", body)

      assert %{"data" => %{"attributes" => %{"status" => "completed"}}} = json_response(conn, 200)
      assert {:ok, %Core.WorkOrder{status: :completed}} = Core.get_work_order(work_order.id)
    end
  end
end
