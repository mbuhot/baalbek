defmodule ServerWeb.CustomerJsonApiTest do
  @moduledoc """
  Exercises `/api/json/core/customers` end to end — real HTTP requests
  through `ServerWeb.Endpoint`, hitting the real `core` schema/role, never
  a stub (seed.md §7's governing principle).
  """

  use ServerWeb.ConnCase, async: true

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Core.Data.Repo)
  end

  defp create_customer!(attrs \\ %{}) do
    Map.merge(%{name: "Acme Facilities", email: "ops@acme.test", phone: "555-0100"}, attrs)
    |> Core.create_customer!()
  end

  describe "POST /customers" do
    test "creates a customer and returns a JSON:API document", %{conn: conn} do
      body = %{
        "data" => %{
          "type" => "customer",
          "attributes" => %{"name" => "Acme Facilities", "email" => "ops@acme.test"}
        }
      }

      conn = post(conn, "/api/json/core/customers", body)

      assert %{"data" => data} = json_response(conn, 201)
      assert data["type"] == "customer"
      assert data["attributes"]["name"] == "Acme Facilities"
      assert data["attributes"]["email"] == "ops@acme.test"
      assert {:ok, _} = Ecto.UUID.cast(data["id"])

      # Written through `Core`, not simulated — a real row exists.
      assert {:ok, %Core.Customer{name: "Acme Facilities"}} = Core.get_customer(data["id"])
    end

    test "rejects a customer with no name", %{conn: conn} do
      body = %{"data" => %{"type" => "customer", "attributes" => %{"email" => "x@test.com"}}}

      conn = post(conn, "/api/json/core/customers", body)

      assert %{"errors" => [%{"source" => %{"pointer" => "/data/attributes/name"}}]} =
               json_response(conn, 400)
    end
  end

  describe "GET /customers" do
    test "lists customers created via Core", %{conn: conn} do
      create_customer!(%{name: "Acme Facilities"})
      create_customer!(%{name: "Widgets Inc", email: "ops@widgets.test"})

      conn = get(conn, "/api/json/core/customers")

      assert %{"data" => data} = json_response(conn, 200)
      assert length(data) == 2
      assert Enum.all?(data, &(&1["type"] == "customer"))
      names = Enum.map(data, & &1["attributes"]["name"]) |> Enum.sort()
      assert names == ["Acme Facilities", "Widgets Inc"]
    end
  end

  describe "GET /customers/:id" do
    test "fetches a single customer", %{conn: conn} do
      customer = create_customer!()

      conn = get(conn, "/api/json/core/customers/#{customer.id}")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == customer.id
      assert data["attributes"]["name"] == customer.name
    end

    test "404s for an id that doesn't exist", %{conn: conn} do
      conn = get(conn, "/api/json/core/customers/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404)
    end
  end

  describe "PATCH /customers/:id" do
    test "updates a customer via Core.update_customer/2", %{conn: conn} do
      customer = create_customer!()

      body = %{
        "data" => %{
          "type" => "customer",
          "id" => customer.id,
          "attributes" => %{"name" => "Acme Facilities Group"}
        }
      }

      conn = patch(conn, "/api/json/core/customers/#{customer.id}", body)

      assert %{"data" => data} = json_response(conn, 200)
      assert data["attributes"]["name"] == "Acme Facilities Group"
      assert {:ok, %Core.Customer{name: "Acme Facilities Group"}} = Core.get_customer(customer.id)
    end
  end

  describe "DELETE /customers/:id" do
    test "destroys a customer via Core.destroy_customer/1", %{conn: conn} do
      customer = create_customer!()

      conn = delete(conn, "/api/json/core/customers/#{customer.id}")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == customer.id
      assert {:error, %Ash.Error.Invalid{}} = Core.get_customer(customer.id)
    end
  end
end
