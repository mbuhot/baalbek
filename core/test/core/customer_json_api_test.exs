defmodule Core.CustomerJsonApiTest do
  @moduledoc """
  Exercises `/customers` end to end — the router driven as a
  Plug, hitting the real `core` schema and role,
  never a stub.
  """

  use Core.JsonApiCase, async: true

  defp create_customer!(attrs \\ %{}) do
    Map.merge(%{name: "Acme Facilities", email: "ops@acme.test", phone: "555-0100"}, attrs)
    |> Core.create_customer!()
  end

  describe "POST /customers" do
    test "creates a customer and returns a JSON:API document" do
      body = %{
        "data" => %{
          "type" => "customer",
          "attributes" => %{"name" => "Acme Facilities", "email" => "ops@acme.test"}
        }
      }

      {status, doc} = request(:post, "/customers", body)

      assert status == 201
      assert %{"data" => data} = doc
      assert data["type"] == "customer"
      assert data["attributes"]["name"] == "Acme Facilities"
      assert data["attributes"]["email"] == "ops@acme.test"
      assert {:ok, _} = Ecto.UUID.cast(data["id"])

      # Written through `Core`, not simulated — a real row exists.
      assert {:ok, %Core.Customer{name: "Acme Facilities"}} = Core.get_customer(data["id"])
    end

    test "rejects a customer with no name" do
      body = %{"data" => %{"type" => "customer", "attributes" => %{"email" => "x@test.com"}}}

      {status, doc} = request(:post, "/customers", body)

      assert status == 400
      assert %{"errors" => [%{"source" => %{"pointer" => "/data/attributes/name"}}]} = doc
    end
  end

  describe "GET /customers" do
    test "lists customers created via Core" do
      acme = create_customer!(%{name: "Acme Facilities"})
      widgets = create_customer!(%{name: "Widgets Inc", email: "ops@widgets.test"})

      {status, doc} = request(:get, "/customers")

      assert status == 200
      assert %{"data" => data} = doc
      assert Enum.all?(data, &(&1["type"] == "customer"))

      # Matched by id, not by row count: the sandbox transaction still sees
      # rows anything else committed to the `core` schema, such as a release
      # run or an e2e pass, so an absolute count is not this test's to assert.
      mine = Enum.filter(data, &(&1["id"] in [acme.id, widgets.id]))
      names = Enum.map(mine, & &1["attributes"]["name"]) |> Enum.sort()
      assert names == ["Acme Facilities", "Widgets Inc"]
    end
  end

  describe "GET /customers/:id" do
    test "fetches a single customer" do
      customer = create_customer!()

      {status, doc} = request(:get, "/customers/#{customer.id}")

      assert status == 200
      assert %{"data" => data} = doc
      assert data["id"] == customer.id
      assert data["attributes"]["name"] == customer.name
    end

    test "404s for an id that doesn't exist" do
      {status, _doc} = request(:get, "/customers/#{Ecto.UUID.generate()}")

      assert status == 404
    end
  end

  describe "PATCH /customers/:id" do
    test "updates a customer via Core.update_customer/2" do
      customer = create_customer!()

      body = %{
        "data" => %{
          "type" => "customer",
          "id" => customer.id,
          "attributes" => %{"name" => "Acme Facilities Group"}
        }
      }

      {status, doc} = request(:patch, "/customers/#{customer.id}", body)

      assert status == 200
      assert %{"data" => data} = doc
      assert data["attributes"]["name"] == "Acme Facilities Group"
      assert {:ok, %Core.Customer{name: "Acme Facilities Group"}} = Core.get_customer(customer.id)
    end
  end

  describe "DELETE /customers/:id" do
    test "destroys a customer via Core.destroy_customer/1" do
      customer = create_customer!()

      {status, doc} = request(:delete, "/customers/#{customer.id}")

      assert status == 200
      assert %{"data" => data} = doc
      assert data["id"] == customer.id
      assert {:error, %Ash.Error.Invalid{}} = Core.get_customer(customer.id)
    end
  end
end
