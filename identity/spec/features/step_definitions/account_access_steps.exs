defmodule Identity.Spec.AccountAccessSteps do
  @moduledoc "Steps for spec/features/account_access.feature, driving the real `Identity.Accounts` code interface."

  use Cucumber.StepDefinition
  import ExUnit.Assertions

  step "a technician account for {string} with password {string}",
       %{args: [email, password]} = context do
    {:ok, account} = register(:technician, email, password)
    Map.put(context, :account, account)
  end

  step "a dispatcher account for {string} with password {string}",
       %{args: [email, password]} = context do
    {:ok, account} = register(:dispatcher, email, password)
    Map.put(context, :account, account)
  end

  step "a technician account is registered for {string} with password {string}",
       %{args: [email, password]} = context do
    Map.put(context, :last_result, register(:technician, email, password))
  end

  step "a second dispatcher account is registered for {string}", %{args: [email]} = context do
    Map.put(context, :last_result, register(:dispatcher, email, "another long password"))
  end

  step "the stored account never holds the password {string}", %{args: [password]} = context do
    refute context.account.hashed_password == password
    context
  end

  step "the account password is changed to {string}", %{args: [password]} = context do
    {:ok, account} = Identity.Accounts.change_password(context.account, %{password: password})
    Map.put(context, :account, account)
  end

  step "{string} signs in with {string}", %{args: [email, password]} = context do
    Map.put(context, :sign_in, Identity.Accounts.authenticate(email, password))
  end

  step "sign-in succeeds", context do
    assert {:ok, %Identity.Accounts.Account{}} = context.sign_in
    context
  end

  step "sign-in fails", context do
    assert {:error, _reason} = context.sign_in
    context
  end

  step "registration is rejected", context do
    assert {:error, %Ash.Error.Invalid{}} = context.last_result
    context
  end

  defp register(role, email, password) do
    Identity.Accounts.register(%{
      name: "Jamie Rivera",
      email: email,
      role: role,
      password: password
    })
  end
end
