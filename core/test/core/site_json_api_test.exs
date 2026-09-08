defmodule Core.SiteJsonApiTest do
  @moduledoc "Exercises `/sites` end to end against the real `core` schema/role."

  use Core.JsonApiCase, async: true

  defp create_customer! do
    Core.create_customer!(%{name: "Acme Facilities", email: "ops@acme.test"})
  end

  describe "POST /sites" do
    test "creates a site for a customer" do
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

      {status, doc} = request(:post, "/sites", body)

      assert status == 201
      assert %{"data" => data} = doc
      assert data["attributes"]["name"] == "Warehouse 1"
      assert data["attributes"]["customer_id"] == customer.id
      assert {:ok, %Core.Site{}} = Core.get_site(data["id"])
    end
  end

  describe "GET /sites and GET /sites/:id" do
    test "lists then fetches a site" do
      customer = create_customer!()

      site =
        Core.create_site!(%{name: "Warehouse 1", address: "1 Dock Rd", customer_id: customer.id})

      {status, doc} = request(:get, "/sites")
      assert status == 200
      assert %{"data" => [_ | _] = data} = doc
      assert Enum.any?(data, &(&1["id"] == site.id))

      {status, doc} = request(:get, "/sites/#{site.id}")
      assert status == 200
      assert %{"data" => %{"id" => id}} = doc
      assert id == site.id
    end
  end

  describe "PATCH and DELETE /sites/:id" do
    test "updates then destroys a site" do
      customer = create_customer!()

      site =
        Core.create_site!(%{name: "Warehouse 1", address: "1 Dock Rd", customer_id: customer.id})

      patch_body = %{
        "data" => %{"type" => "site", "id" => site.id, "attributes" => %{"name" => "Warehouse 2"}}
      }

      {status, doc} = request(:patch, "/sites/#{site.id}", patch_body)

      assert status == 200
      assert %{"data" => %{"attributes" => %{"name" => "Warehouse 2"}}} = doc

      {status, _doc} = request(:delete, "/sites/#{site.id}")
      assert status == 200
      assert {:error, %Ash.Error.Invalid{}} = Core.get_site(site.id)
    end
  end
end
