defmodule Hybridsocial.Federation.HTTPMessageSignatureTest do
  # End-to-end RFC 9421 verification through HTTPSignature.verify/1, with the
  # sender's actor served by a Req.Test stub (as in http_signature_verify_test).
  # async: false: instance keys and the fetch seam are app env.
  use ExUnit.Case, async: false

  alias Hybridsocial.Federation.{HTTPMessageSignature, HTTPSignature}

  defp keypair do
    priv = :public_key.generate_key({:rsa, 2048, 65_537})
    priv_pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, priv)])
    pub = {:RSAPublicKey, elem(priv, 2), elem(priv, 3)}
    pub_pem = :public_key.pem_encode([:public_key.pem_entry_encode(:SubjectPublicKeyInfo, pub)])
    {priv, pub_pem}
  end

  setup do
    {_ipriv, ipub} = keypair()
    {ipriv_key, _} = keypair()

    Application.put_env(
      :hybridsocial,
      :instance_private_key,
      :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, ipriv_key)])
    )

    Application.put_env(:hybridsocial, :instance_public_key, ipub)

    Application.put_env(:hybridsocial, :http_signature_fetch_options,
      plug: {Req.Test, __MODULE__}
    )

    on_exit(fn ->
      Application.delete_env(:hybridsocial, :instance_private_key)
      Application.delete_env(:hybridsocial, :instance_public_key)
      Application.delete_env(:hybridsocial, :http_signature_fetch_options)
    end)

    actor = "https://mastodon.example/users/u#{System.unique_integer([:positive])}"
    key_id = actor <> "#main-key"
    {priv, pub_pem} = keypair()

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "id" => actor,
        "publicKey" => %{"id" => key_id, "owner" => actor, "publicKeyPem" => pub_pem}
      })
    end)

    %{key_id: key_id, priv: priv}
  end

  @body ~s({"type":"Create","id":"https://mastodon.example/a/1"})

  # Builds RFC 9421 headers the way Mastodon's signer (linzer) does, writing
  # the signature base out by hand rather than reusing the verifier's code.
  defp signed_conn(ctx, opts \\ []) do
    now = System.os_time(:second)
    created = Keyword.get(opts, :created, now)
    target = Keyword.get(opts, :target, HybridsocialWeb.Endpoint.url() <> "/inbox")
    components = Keyword.get(opts, :components, ~w(@method @target-uri content-digest))
    alg = Keyword.get(opts, :alg, "rsa-v1_5-sha256")
    extra = Keyword.get(opts, :extra_params, "")
    body = Keyword.get(opts, :sent_body, @body)
    digest = "sha-256=:#{Base.encode64(:crypto.hash(:sha256, @body))}:"

    params =
      "(" <>
        Enum.map_join(components, " ", &~s("#{&1}")) <>
        ")" <>
        ~s(;created=#{created};keyid="#{ctx.key_id}";alg="#{alg}") <> extra

    lines =
      Enum.map(components, fn
        "@method" -> ~s("@method": POST)
        "@target-uri" -> ~s("@target-uri": #{target})
        "content-digest" -> ~s("content-digest": #{digest})
      end)

    base = Enum.join(lines ++ [~s("@signature-params": #{params})], "\n")

    sig =
      case alg do
        "rsa-pss-sha512" ->
          :public_key.sign(base, :sha512, ctx.priv,
            rsa_padding: :rsa_pkcs1_pss_padding,
            rsa_pss_saltlen: 64,
            rsa_mgf1_md: :sha512
          )

        _ ->
          :public_key.sign(base, :sha256, ctx.priv)
      end

    Plug.Test.conn(:post, "/inbox", body)
    |> Plug.Conn.put_req_header("content-digest", digest)
    |> Plug.Conn.put_req_header("signature-input", "sig1=" <> params)
    |> Plug.Conn.put_req_header("signature", "sig1=:#{Base.encode64(sig)}:")
  end

  test "verifies a Mastodon-style RFC 9421 signature", ctx do
    assert {:ok, key_id} = HTTPSignature.verify(signed_conn(ctx))
    assert key_id == ctx.key_id
  end

  test "verifies rsa-pss-sha512", ctx do
    assert {:ok, _} = HTTPSignature.verify(signed_conn(ctx, alg: "rsa-pss-sha512"))
  end

  test "rejects a POST whose signature doesn't cover content-digest", ctx do
    assert {:error, :digest_not_signed} =
             HTTPSignature.verify(signed_conn(ctx, components: ~w(@method @target-uri)))
  end

  test "rejects a signature without the target covered", ctx do
    assert {:error, :insufficient_coverage} =
             HTTPSignature.verify(signed_conn(ctx, components: ~w(@method content-digest)))
  end

  test "rejects a request signed for another server (replayed to us)", ctx do
    assert {:error, :invalid_signature} =
             HTTPSignature.verify(signed_conn(ctx, target: "https://other.example/inbox"))
  end

  test "enforces created and expires", ctx do
    now = System.os_time(:second)

    assert {:error, :signature_too_old} =
             HTTPSignature.verify(signed_conn(ctx, created: now - 13 * 3600))

    assert {:error, :created_in_future} =
             HTTPSignature.verify(signed_conn(ctx, created: now + 2 * 3600))

    assert {:error, :signature_expired} =
             HTTPSignature.verify(signed_conn(ctx, extra_params: ";expires=#{now - 2 * 3600}"))
  end

  test "refuses algorithms we don't support", ctx do
    assert {:error, :unsupported_algorithm} =
             HTTPSignature.verify(signed_conn(ctx, alg: "ed25519"))
  end

  test "a forged signature is rejected", ctx do
    {other_priv, _} = keypair()

    assert {:error, :invalid_signature} =
             HTTPSignature.verify(signed_conn(%{ctx | priv: other_priv}))
  end

  describe "verify_content_digest/2" do
    test "matches sha-256 and sha-512, rejects tampering and unknown algorithms" do
      d256 = "sha-256=:#{Base.encode64(:crypto.hash(:sha256, @body))}:"
      d512 = "sha-512=:#{Base.encode64(:crypto.hash(:sha512, @body))}:"

      assert :ok = HTTPMessageSignature.verify_content_digest(d256, @body)
      assert :ok = HTTPMessageSignature.verify_content_digest("#{d256}, #{d512}", @body)

      assert {:error, :digest_mismatch} =
               HTTPMessageSignature.verify_content_digest(d256, @body <> " ")

      assert {:error, :unsupported_digest} =
               HTTPMessageSignature.verify_content_digest("md5=:AAAA:", @body)
    end
  end

  test "parse_dictionary keeps commas inside strings and inner lists" do
    assert [
             {"sig1", ~s|("@method" "@target-uri");keyid="https://x.example/a,b#k"|},
             {"sig2", "(\"@method\")"}
           ] =
             HTTPMessageSignature.parse_dictionary(
               ~s|sig1=("@method" "@target-uri");keyid="https://x.example/a,b#k", sig2=("@method")|
             )
  end
end
