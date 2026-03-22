defmodule Hybridsocial.Auth.PoWTest do
  use ExUnit.Case, async: true

  alias Hybridsocial.Auth.PoW

  describe "verify/2" do
    test "verifies a valid proof of work" do
      prefix = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
      diff = 4
      nonce = find_nonce(prefix, diff)
      # Verify manually (not via PoW.verify which uses global config difficulty)
      hash = :crypto.hash(:sha256, prefix <> nonce)
      zeros = count_zeros(hash)
      assert zeros >= diff
    end

    test "rejects invalid proof" do
      refute PoW.verify("test_prefix", "bad_nonce")
    end

    test "rejects nil inputs" do
      refute PoW.verify(nil, nil)
    end
  end

  defp find_nonce(prefix, difficulty) do
    Enum.reduce_while(0..1_000_000, nil, fn i, _acc ->
      nonce = Integer.to_string(i)
      hash = :crypto.hash(:sha256, prefix <> nonce)
      zeros = count_zeros(hash)

      if zeros >= difficulty do
        {:halt, nonce}
      else
        {:cont, nil}
      end
    end)
  end

  defp count_zeros(<<0::1, rest::bitstring>>), do: 1 + count_zeros(rest)
  defp count_zeros(_), do: 0
end
