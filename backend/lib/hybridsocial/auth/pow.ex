defmodule Hybridsocial.Auth.PoW do
  @moduledoc "Proof of Work challenge for abuse-prone endpoints."

  alias Hybridsocial.Config

  def enabled? do
    Config.get("pow_enabled", false) == true
  end

  def difficulty do
    Config.get("pow_difficulty", 16)
  end

  def generate_challenge(diff \\ nil) do
    diff = diff || difficulty()
    prefix = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    expires_at = DateTime.add(DateTime.utc_now(), 300, :second)

    # Store in cache with 5 min TTL
    try do
      Hybridsocial.Cache.set("pow:#{prefix}", %{difficulty: diff}, 300)
    rescue
      _ -> :ok
    end

    %{prefix: prefix, difficulty: diff, expires_at: expires_at}
  end

  def verify(prefix, nonce) when is_binary(prefix) and is_binary(nonce) do
    diff = difficulty()
    hash = :crypto.hash(:sha256, prefix <> nonce)
    leading_zeros = count_leading_zero_bits(hash)
    leading_zeros >= diff
  end

  def verify(_, _), do: false

  defp count_leading_zero_bits(<<0::1, rest::bitstring>>), do: 1 + count_leading_zero_bits(rest)
  defp count_leading_zero_bits(_), do: 0
end
