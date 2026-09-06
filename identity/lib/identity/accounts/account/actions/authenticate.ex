defmodule Identity.Accounts.Account.Actions.Authenticate do
  @moduledoc """
  Looks an account up by email and verifies its password, returning the same error for either failure so a caller can't enumerate registered emails.
  """

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  @doc "Verifies email/password credentials and returns the matching account or a generic invalid-credentials error."
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
