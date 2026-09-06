defmodule Identity.Accounts.Account.Changes.HashPassword do
  @moduledoc """
  Ash change that hashes the `:password` argument (present on `:register`
  and `:change_password`) into the `:hashed_password` attribute via
  `Identity.Accounts.PasswordHasher` — the plaintext password is never
  persisted or stored on the changeset's data.
  """

  use Ash.Resource.Change

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
