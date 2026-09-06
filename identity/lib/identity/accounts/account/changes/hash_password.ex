defmodule Identity.Accounts.Account.Changes.HashPassword do
  @moduledoc """
  Ash change that hashes the `:password` argument into `:hashed_password` via `Identity.Accounts.PasswordHasher`.
  """

  use Ash.Resource.Change

  @doc "Hashes the given :password argument and force-sets :hashed_password, leaving the changeset untouched when no password was given."
  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_argument(changeset, :password) do
      nil ->
        changeset

      password ->
        Ash.Changeset.force_change_attribute(
          changeset,
          :hashed_password,
          Identity.Accounts.PasswordHasher.hash(password)
        )
    end
  end
end
