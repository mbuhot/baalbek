defmodule ServerWeb.SiteJsonApiTest do
  @moduledoc "Exercises `/api/json/core/sites` end to end against the real `core` schema/role."

  use ServerWeb.ConnCase, async: true

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Core.Data.Repo)
  end

  defp create_customer! do
    Core.create_customer!(%{name: "Acme Facilities", email: "ops@acme.test"})
  end

  describe "POST /sites" do
    test "creates a site for a customer", %{conn: conn} do
      customer = create_customer!()

      body = %{
        "data" => %{
          "type" => "site",
          "attributes" => %{
            "name" => "Warehouse 1",
            "address" => "1 Dock Rd",
            "customer_id" => customer.id
          }
        }
      }

      conn = post(conn, "/api/json/core/sites", body)

      assert %{"data" => data} = json_response(conn, 201)
      assert data["attributes"]["name"] == "Warehouse 1"
      assert data["attributes"]["customer_id"] == customer.id
      assert {:ok, %Core.Site{}} = Core.get_site(data["id"])
    end
  end

  describe "GET /sites and GET /sites/:id" do
    test "lists then fetches a site", %{conn: conn} do
      customer = create_customer!()

      site =
        Core.create_site!(%{name: "Warehouse 1", address: "1 Dock Rd", customer_id: customer.id})

      list_conn = get(conn, "/api/json/core/sites")
      assert %{"data" => [_ | _] = data} = json_response(list_conn, 200)
      assert Enum.any?(data, &(&1["id"] == site.id))

      get_conn = get(conn, "/api/json/core/sites/#{site.id}")
      assert %{"data" => %{"id" => id}} = json_response(get_conn, 200)
      assert id == site.id
    end
  end

  describe "PATCH and DELETE /sites/:id" do
    test "updates then destroys a site", %{conn: conn} do
      customer = create_customer!()

      site =
        Core.create_site!(%{name: "Warehouse 1", address: "1 Dock Rd", customer_id: customer.id})

      patch_body = %{
        "data" => %{"type" => "site", "id" => site.id, "attributes" => %{"name" => "Warehouse 2"}}
      }

      patch_conn = patch(conn, "/api/json/core/sites/#{site.id}", patch_body)

      assert %{"data" => %{"attributes" => %{"name" => "Warehouse 2"}}} =
               json_response(patch_conn, 200)

      delete_conn = delete(conn, "/api/json/core/sites/#{site.id}")
      assert json_response(delete_conn, 200)
      assert {:error, %Ash.Error.Invalid{}} = Core.get_site(site.id)
    end
  end
end
