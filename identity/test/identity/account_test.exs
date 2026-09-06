defmodule Identity.AccountTest do
  @moduledoc """
  Exercises `Identity.Accounts.Account`'s Ash actions — registration,
  authentication, password change, and validation — against the real
  `identity` schema/role. Per seed.md §7's governing principle, this suite
  must be a real proof, runnable alone, never stubbed against a fake data
  layer or a fake password check.
  """

  use ExUnit.Case, async: true

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Identity.Repo)
  end

  defp register!(attrs) do
    Identity.Accounts.Account
    |> Ash.Changeset.for_create(
      :register,
      Map.merge(
        %{
          name: "Jamie Rivera",
          email: "jamie@example.test",
          role: :technician,
          password: "correct horse battery staple"
        },
        Map.new(attrs)
      )
    )
    |> Ash.create!()
  end

  describe "register" do
    test "hashes the password instead of storing it" do
      account = register!(password: "hunter22")

      refute account.hashed_password == "hunter22"
      assert String.contains?(account.hashed_password, ":")
    end

    test "accepts a technician or a dispatcher role" do
      technician = register!(email: "tech@example.test", role: :technician)
      dispatcher = register!(email: "dispatch@example.test", role: :dispatcher)

      assert technician.role == :technician
      assert dispatcher.role == :dispatcher
    end

    test "rejects a role outside the declared set" do
      assert {:error, %Ash.Error.Invalid{}} =
               Identity.Accounts.Account
               |> Ash.Changeset.for_create(:register, %{
                 name: "Bad Role",
                 email: "bad-role@example.test",
                 role: :not_a_real_role,
                 password: "hunter22222"
               })
               |> Ash.create()
    end

    test "rejects a password shorter than 8 characters" do
      assert {:error, %Ash.Error.Invalid{}} =
               Identity.Accounts.Account
               |> Ash.Changeset.for_create(:register, %{
                 name: "Short Password",
                 email: "short@example.test",
                 role: :technician,
                 password: "short"
               })
               |> Ash.create()
    end

    test "rejects a duplicate email" do
      register!(email: "dupe@example.test")

      assert {:error, %Ash.Error.Invalid{}} =
               Identity.Accounts.Account
               |> Ash.Changeset.for_create(:register, %{
                 name: "Second Person",
                 email: "dupe@example.test",
                 role: :dispatcher,
                 password: "hunter22222"
               })
               |> Ash.create()
    end

    test "requires a name" do
      assert {:error, %Ash.Error.Invalid{}} =
               Identity.Accounts.Account
               |> Ash.Changeset.for_create(:register, %{
                 email: "no-name@example.test",
                 role: :technician,
                 password: "hunter22222"
               })
               |> Ash.create()
    end
  end

  describe "authenticate" do
    test "succeeds with the correct email and password" do
      account = register!(email: "auth-ok@example.test", password: "hunter22222")

      assert {:ok, %Identity.Accounts.Account{id: id}} =
               Identity.Accounts.Account
               |> Ash.ActionInput.for_action(:authenticate, %{
                 email: "auth-ok@example.test",
                 password: "hunter22222"
               })
               |> Ash.run_action()

      assert id == account.id
    end

    test "fails with the wrong password" do
      register!(email: "auth-bad@example.test", password: "hunter22222")

      assert {:error, _error} =
               Identity.Accounts.Account
               |> Ash.ActionInput.for_action(:authenticate, %{
                 email: "auth-bad@example.test",
                 password: "totally wrong password"
               })
               |> Ash.run_action()
    end

    test "fails for an unknown email" do
      assert {:error, _error} =
               Identity.Accounts.Account
               |> Ash.ActionInput.for_action(:authenticate, %{
                 email: "nobody@example.test",
                 password: "whatever password"
               })
               |> Ash.run_action()
    end
  end

  describe "change_password" do
    test "the old password stops working and the new one works" do
      account = register!(email: "change-pw@example.test", password: "original password")

      updated =
        account
        |> Ash.Changeset.for_update(:change_password, %{password: "new password 123"})
        |> Ash.update!()

      refute updated.hashed_password == account.hashed_password

      assert {:error, _error} =
               Identity.Accounts.Account
               |> Ash.ActionInput.for_action(:authenticate, %{
                 email: "change-pw@example.test",
                 password: "original password"
               })
               |> Ash.run_action()

      assert {:ok, %Identity.Accounts.Account{}} =
               Identity.Accounts.Account
               |> Ash.ActionInput.for_action(:authenticate, %{
                 email: "change-pw@example.test",
                 password: "new password 123"
               })
               |> Ash.run_action()
    end
  end

  describe "Identity.Accounts code interface" do
    test "register/authenticate/change_password are exposed via the domain" do
      {:ok, account} =
        Identity.Accounts.register(%{
          name: "Code Interface",
          email: "code-interface@example.test",
          role: :dispatcher,
          password: "hunter222222"
        })

      assert {:ok, %Identity.Accounts.Account{id: authenticated_id}} =
               Identity.Accounts.authenticate("code-interface@example.test", "hunter222222")

      assert authenticated_id == account.id

      assert {:ok, updated} =
               Identity.Accounts.change_password(account, %{password: "hunter333333"})

      refute updated.hashed_password == account.hashed_password
    end
  end
end
