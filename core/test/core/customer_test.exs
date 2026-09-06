defmodule Core.CustomerTest do
  @moduledoc """
  Exercises `Core.Customer`'s actions against the real `core` schema/role —
  per seed.md §7's governing principle, this suite must be a real proof,
  runnable alone, never stubbed against a fake data layer.
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

  test "create and read" do
    customer = create_customer!()

    assert customer.name == "Acme Facilities"
    assert customer.email == "ops@acme.test"
    assert %DateTime{} = customer.inserted_at

    assert {:ok, fetched} = Ash.get(Core.Customer, customer.id)
    assert fetched.id == customer.id
  end

  test "update" do
    customer = create_customer!()

    updated =
      customer
      |> Ash.Changeset.for_update(:update, %{name: "Acme Facilities Group"})
      |> Ash.update!()

    assert updated.name == "Acme Facilities Group"
    assert {:ok, %{name: "Acme Facilities Group"}} = Ash.get(Core.Customer, customer.id)
  end

  test "requires a name" do
    assert {:error, %Ash.Error.Invalid{}} =
             Core.Customer
             |> Ash.Changeset.for_create(:create, %{email: "no-name@acme.test"})
             |> Ash.create()
  end

  test "destroy" do
    customer = create_customer!()

    assert :ok = Ash.destroy(customer)
    assert {:error, %Ash.Error.Invalid{}} = Ash.get(Core.Customer, customer.id)
  end
end
