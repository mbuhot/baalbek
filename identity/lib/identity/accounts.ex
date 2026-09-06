defmodule Identity.Accounts do
  @moduledoc """
  The `identity` domain: technician and dispatcher accounts, with registration, authentication, and password-change actions.
  """

  use Ash.Domain,
    otp_app: :identity,
    extensions: [AshBoundary]

  boundary do
    deps [Identity.Repo]
  end

  resources do
    resource Identity.Accounts.Account do
      define :register, action: :register
      define :authenticate, action: :authenticate, args: [:email, :password]
      define :change_password, action: :change_password
    end
  end
end
