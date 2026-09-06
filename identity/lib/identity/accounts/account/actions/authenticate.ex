defmodule Identity.Accounts.Account.Actions.Authenticate do
  @moduledoc """
  Ash generic-action implementation backing `Identity.Accounts.Account`'s
  `:authenticate` action — the actual auth logic requested by PLAN.md's
  identity component ("Technicians, dispatchers, auth."), exercised by
  tests rather than left as a bare unused password field.

  Looks the account up by email, then verifies the given plaintext
  password against the stored `hashed_password` via
  `Identity.Accounts.PasswordHasher.verify/2`. Both "no such email" and
  "wrong password" return the same generic invalid-credentials error, so a
  failed lookup can't be used to enumerate registered emails.
  """

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  @impl true
  def run(input, _opts, _context) do
    email = input.arguments.email
    password = input.arguments.password

    Identity.Accounts.Account
    |> Ash.Query.filter(email == ^email)
    |> Ash.read_one()
    |> case do
      {:ok, %Identity.Accounts.Account{hashed_password: hashed_password} = account} ->
        if Identity.Accounts.PasswordHasher.verify(password, hashed_password) do
          {:ok, account}
        else
          {:error, invalid_credentials_error()}
        end

      {:ok, nil} ->
        {:error, invalid_credentials_error()}

      {:error, error} ->
        {:error, error}
    end
  end

  defp invalid_credentials_error do
    Ash.Error.Changes.InvalidArgument.exception(
      field: :password,
      message: "invalid email or password"
    )
  end
end
