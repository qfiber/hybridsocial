defmodule Hybridsocial.Auth.TOTP do
  @moduledoc """
  Handles TOTP (Time-based One-Time Password) operations per RFC 6238.
  Uses NimbleTOTP for secret generation, URI building, and code validation.
  """

  @issuer "HybridSocial"

  @doc """
  Generates a new random TOTP secret (20 bytes, base32-encoded internally by NimbleTOTP).
  Returns raw binary secret.
  """
  def generate_secret do
    NimbleTOTP.secret()
  end

  @doc """
  Generates an otpauth:// URI suitable for QR code scanning.
  """
  def generate_uri(secret, email) do
    NimbleTOTP.otpauth_uri("#{@issuer}:#{email}", secret, issuer: @issuer)
  end

  @doc """
  Validates a TOTP code against the given secret.
  Accepts string codes (6-digit) and converts them for verification.
  """
  def valid_code?(secret, code) when is_binary(code) do
    NimbleTOTP.valid?(secret, code)
  end

  def valid_code?(_secret, _code), do: false

  @doc """
  Generates a list of recovery codes.
  Each code is an 8-character alphanumeric string.
  """
  def generate_recovery_codes(count \\ 8) do
    alphabet = ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    alphabet_size = length(alphabet)

    Enum.map(1..count, fn _ ->
      1..8
      |> Enum.map(fn _ -> Enum.at(alphabet, :rand.uniform(alphabet_size) - 1) end)
      |> List.to_string()
    end)
  end
end
