defmodule Hybridsocial.Federation.HTTPSignatureTest do
  use ExUnit.Case, async: true

  alias Hybridsocial.Federation.HTTPSignature

  setup do
    # Generate a test RSA keypair
    private_key = :public_key.generate_key({:rsa, 2048, 65537})
    private_entry = :public_key.pem_entry_encode(:RSAPrivateKey, private_key)
    private_pem = :public_key.pem_encode([private_entry])

    rsa_public = {:RSAPublicKey, elem(private_key, 2), elem(private_key, 3)}
    public_entry = :public_key.pem_entry_encode(:SubjectPublicKeyInfo, rsa_public)
    public_pem = :public_key.pem_encode([public_entry])

    %{private_pem: private_pem, public_pem: public_pem}
  end

  describe "sign/3" do
    test "returns a map with required headers", %{private_pem: private_pem} do
      request = %{
        method: "POST",
        url: "https://remote.example/inbox",
        body: ~s({"type": "Create"})
      }

      key_id = "https://local.example/actors/123#main-key"
      headers = HTTPSignature.sign(request, private_pem, key_id)

      assert Map.has_key?(headers, "Signature")
      assert Map.has_key?(headers, "Date")
      assert Map.has_key?(headers, "Digest")
      assert Map.has_key?(headers, "Host")

      assert headers["Host"] == "remote.example"
      assert String.starts_with?(headers["Digest"], "SHA-256=")
      assert String.contains?(headers["Signature"], ~s(keyId="#{key_id}"))
      assert String.contains?(headers["Signature"], ~s(algorithm="rsa-sha256"))
    end
  end

  describe "build_signing_string/2" do
    test "constructs correct signing string" do
      headers = ["(request-target)", "host", "date"]

      request_data = %{
        "(request-target)" => "post /inbox",
        "host" => "remote.example",
        "date" => "Sun, 22 Mar 2026 12:00:00 GMT"
      }

      result = HTTPSignature.build_signing_string(headers, request_data)

      expected =
        "(request-target): post /inbox\nhost: remote.example\ndate: Sun, 22 Mar 2026 12:00:00 GMT"

      assert result == expected
    end
  end

  describe "sign and verify round-trip" do
    test "a signed request can be verified", %{private_pem: private_pem, public_pem: public_pem} do
      request = %{
        method: "POST",
        url: "https://remote.example/inbox",
        body: ~s({"type": "Create"})
      }

      key_id = "https://local.example/actors/123#main-key"
      signed_headers = HTTPSignature.sign(request, private_pem, key_id)

      # Verify the signature manually
      sig_header = signed_headers["Signature"]

      # Parse signature params
      params =
        sig_header
        |> String.split(",")
        |> Enum.map(fn part ->
          [key, value] = String.split(part, "=", parts: 2)
          {String.trim(key), String.trim(value, "\"")}
        end)
        |> Map.new()

      headers_to_verify = String.split(params["headers"], " ")

      request_data = %{
        "(request-target)" => "post /inbox",
        "host" => signed_headers["Host"],
        "date" => signed_headers["Date"],
        "digest" => signed_headers["Digest"]
      }

      signing_string = HTTPSignature.build_signing_string(headers_to_verify, request_data)

      [pem_entry] = :public_key.pem_decode(public_pem)
      pub_key = :public_key.pem_entry_decode(pem_entry)
      signature = Base.decode64!(params["signature"])

      assert :public_key.verify(signing_string, :sha256, signature, pub_key)
    end
  end
end
