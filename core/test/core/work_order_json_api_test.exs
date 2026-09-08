defmodule Core.WorkOrderJsonApiTest do
  @moduledoc "Exercises `/work_orders` end to end against the real `core` schema/role."

  use Core.JsonApiCase, async: true

  defp create_job! do
    customer = Core.create_customer!(%{name: "Acme Facilities", email: "ops@acme.test"})

    site =
      Core.create_site!(%{name: "Warehouse 1", address: "1 Dock Rd", customer_id: customer.id})

    Core.create_job!(%{title: "Fix conveyor", site_id: site.id})
  end

  describe "POST /work_orders" do
    test "opens a new work order against a job" do
      job = create_job!()

      body = %{
        "data" => %{
          "type" => "work_order",
          "attributes" => %{"summary" => "Initial visit", "job_id" => job.id}
        }
      }

      {status, doc} = request(:post, "/work_orders", body)

      assert status == 201
      assert %{"data" => data} = doc
      assert data["attributes"]["summary"] == "Initial visit"
      assert data["attributes"]["status"] == "open"
      assert {:ok, %Core.WorkOrder{}} = Core.get_work_order(data["id"])
    end
  end

  describe "GET /work_orders and GET /work_orders/:id" do
    test "lists then fetches a work order" do
      job = create_job!()
      work_order = Core.create_work_order!(%{summary: "Initial visit", job_id: job.id})

      {status, doc} = request(:get, "/work_orders")
      assert status == 200
      assert %{"data" => data} = doc
      assert Enum.any?(data, &(&1["id"] == work_order.id))

      {status, doc} = request(:get, "/work_orders/#{work_order.id}")
      assert status == 200
      assert %{"data" => %{"id" => id}} = doc
      assert id == work_order.id
    end
  end

  describe "PATCH /work_orders/:id" do
    test "marks a work order completed via Core.update_work_order/2" do
      job = create_job!()
      work_order = Core.create_work_order!(%{summary: "Initial visit", job_id: job.id})

      body = %{
        "data" => %{
          "type" => "work_order",
          "id" => work_order.id,
          "attributes" => %{"status" => "completed"}
        }
      }

      {status, doc} = request(:patch, "/work_orders/#{work_order.id}", body)

      assert status == 200
      assert %{"data" => %{"attributes" => %{"status" => "completed"}}} = doc
      assert {:ok, %Core.WorkOrder{status: :completed}} = Core.get_work_order(work_order.id)
    end
  end
end
