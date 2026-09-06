defmodule Identity.Accounts.PasswordHasher do
  @moduledoc """
  Password hashing for `Identity.Accounts.Account` (PLAN.md's identity
  component: "Technicians, dispatchers, auth."). Internal to the
  `Identity.Accounts` boundary — not a resource, has no domain-level
  `define`, so `ash_boundary` leaves it unexported; only
  `Identity.Accounts.Account.Changes.HashPassword` and
  `Identity.Accounts.Account.Actions.Authenticate` call it directly.

  Uses PBKDF2-HMAC-SHA256 via Erlang/OTP's built-in `:crypto` module —
  deliberately no external hashing dependency (e.g. `bcrypt_elixir`,
  `argon2_elixir`) at this stage: `:crypto.pbkdf2_hmac/5` and
  `:crypto.hash_equals/2` (constant-time comparison, avoiding a timing
  side-channel) are both available in the OTP versions this repo already
  pins (`.prototools`), so no new dependency is needed to exercise real
  hash/verify logic.

  Encoded format: `"<iterations>:<base64 salt>:<base64 derived key>"` — the
  iteration count travels with the hash so a future stage could raise it
  without invalidating already-stored hashes (verify/2 reads whatever
  iteration count is embedded, not a hardcoded current default).
  """

  @iterations 100_000
  @salt_bytes 16
  @derived_key_bytes 32

  @doc "Hashes a plaintext password into the encoded storage format."
  @spec hash(String.t()) :: String.t()
  def hash(password) when is_binary(password) do
    salt = :crypto.strong_rand_bytes(@salt_bytes)
    derived = derive(password, salt, @iterations)
    Enum.join([@iterations, Base.encode64(salt), Base.encode64(derived)], ":")
  end

  @doc """
  Verifies a plaintext password against a previously-hashed, encoded value.
  Returns `false` (never raises) for a malformed encoded value, so a
  corrupted/legacy hash fails closed rather than crashing the auth action.
  """
  @spec verify(String.t(), String.t()) :: boolean()
  def verify(password, encoded) when is_binary(password) and is_binary(encoded) do
    with [iterations_str, salt_b64, hash_b64] <- String.split(encoded, ":", parts: 3),
         {iterations, ""} <- Integer.parse(iterations_str),
         {:ok, salt} <- Base.decode64(salt_b64),
         {:ok, expected} <- Base.decode64(hash_b64) do
      actual = derive(password, salt, iterations)
      :crypto.hash_equals(actual, expected)
    else
      _ -> false
    end
  end

  defp derive(password, salt, iterations) do
    :crypto.pbkdf2_hmac(:sha256, password, salt, iterations, @derived_key_bytes)
  end
end
