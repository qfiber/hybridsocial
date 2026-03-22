defmodule Hybridsocial.Auth.TOTPTest do
  use ExUnit.Case, async: true

  alias Hybridsocial.Auth.TOTP

  describe "generate_secret/0" do
    test "returns a binary secret" do
      secret = TOTP.generate_secret()
      assert is_binary(secret)
      assert byte_size(secret) == 20
    end

    test "generates unique secrets" do
      secret1 = TOTP.generate_secret()
      secret2 = TOTP.generate_secret()
      assert secret1 != secret2
    end
  end

  describe "generate_uri/2" do
    test "returns an otpauth URI" do
      secret = TOTP.generate_secret()
      uri = TOTP.generate_uri(secret, "user@example.com")

      assert String.starts_with?(uri, "otpauth://totp/")
      assert uri =~ "HybridSocial"
      assert uri =~ "user%40example.com" or uri =~ "user@example.com"
    end
  end

  describe "valid_code?/2" do
    test "validates a correct TOTP code" do
      secret = TOTP.generate_secret()
      code = NimbleTOTP.verification_code(secret)

      assert TOTP.valid_code?(secret, code) == true
    end

    test "rejects an incorrect code" do
      secret = TOTP.generate_secret()
      assert TOTP.valid_code?(secret, "000000") == false
    end

    test "rejects non-binary code" do
      secret = TOTP.generate_secret()
      assert TOTP.valid_code?(secret, 123_456) == false
    end
  end

  describe "generate_recovery_codes/1" do
    test "generates 8 codes by default" do
      codes = TOTP.generate_recovery_codes()
      assert length(codes) == 8
    end

    test "generates specified number of codes" do
      codes = TOTP.generate_recovery_codes(4)
      assert length(codes) == 4
    end

    test "each code is 8 characters long" do
      codes = TOTP.generate_recovery_codes()

      Enum.each(codes, fn code ->
        assert String.length(code) == 8
      end)
    end

    test "codes are alphanumeric uppercase" do
      codes = TOTP.generate_recovery_codes()

      Enum.each(codes, fn code ->
        assert code =~ ~r/^[A-Z0-9]{8}$/
      end)
    end

    test "codes are unique" do
      codes = TOTP.generate_recovery_codes()
      assert length(Enum.uniq(codes)) == length(codes)
    end
  end
end
