defmodule Identity.Accounts.PasswordHasher do
  @moduledoc """
  Hashes and verifies account passwords using PBKDF2-HMAC-SHA256.

  Callers only need `hash/1` and `verify/2`. The encoded string carries its
  own iteration count, so a future stage can raise it without invalidating
  hashes already stored under a lower count.
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
  Verifies a plaintext password against a previously-hashed, encoded value, returning `false` rather than raising if the encoding is malformed.
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
