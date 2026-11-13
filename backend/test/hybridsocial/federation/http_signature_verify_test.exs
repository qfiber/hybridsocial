defmodule Hybridsocial.Federation.HTTPSignatureVerifyTest do
  # End-to-end inbound verification: a request signed by a "remote" key,
  # whose actor document is served by a Req.Test stub that behaves like a
  # Mastodon secure-mode server (401 to unsigned GETs).
  #
  # async: false: instance keys and the fetch seam are app env.
  use ExUnit.Case, async: false

  alias Hybridsocial.Federation.HTTPSignature

  defp keypair do
    private_key = :public_key.generate_key({:rsa, 2048, 65_537})

    private_pem =
      :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, private_key)])

    rsa_public = {:RSAPublicKey, elem(private_key, 2), elem(private_key, 3)}

    public_pem =
      :public_key.pem_encode([:public_key.pem_entry_encode(:SubjectPublicKeyInfo, rsa_public)])

    {private_pem, public_pem}
  end

  setup do
    {instance_priv, instance_pub} = keypair()
    Application.put_env(:hybridsocial, :instance_private_key, instance_priv)
    Application.put_env(:hybridsocial, :instance_public_key, instance_pub)

    Application.put_env(:hybridsocial, :http_signature_fetch_options,
      plug: {Req.Test, __MODULE__}
    )

    on_exit(fn ->
      Application.delete_env(:hybridsocial, :instance_private_key)
      Application.delete_env(:hybridsocial, :instance_public_key)
      Application.delete_env(:hybridsocial, :http_signature_fetch_options)
    end)

    actor = "https://secure.example/users/u#{System.unique_integer([:positive])}"
    {private_pem, public_pem} = keypair()

    %{
      actor: actor,
      key_id: actor <> "#main-key",
      private_pem: private_pem,
      public_pem: public_pem
    }
  end

  # Serves `actor` with `pem` under `key_id`, but only to SIGNED requests,
  # like Mastodon's authorized fetch. Reports each fetch to the test.
  defp serve_actor(actor, key_id, pem) do
    test_pid = self()

    Req.Test.stub(__MODULE__, fn conn ->
      send(test_pid, {:fetched, Plug.Conn.get_req_header(conn, "signature")})

      if Plug.Conn.get_req_header(conn, "signature") == [] do
        Plug.Conn.send_resp(conn, 401, "")
      else
        Req.Test.json(conn, %{
          "id" => actor,
          "publicKey" => %{"id" => key_id, "owner" => actor, "publicKeyPem" => pem}
        })
      end
    end)
  end

  defp signed_post(private_pem, key_id, body \\ ~s({"type":"Create"})) do
    headers =
      HTTPSignature.sign(
        %{method: "POST", url: "https://bassam.test/inbox", body: body},
        private_pem,
        key_id
      )

    # Plug.Test won't `put_req_header("host", ...)`; real adapters do carry
    # it in req_headers, which is where the verifier reads it.
    Enum.reduce(headers, Plug.Test.conn(:post, "/inbox", body), fn
      {"Host", v}, conn -> %{conn | req_headers: [{"host", v} | conn.req_headers]}
      {k, v}, conn -> Plug.Conn.put_req_header(conn, String.downcase(k), v)
    end)
  end

  defp fetch_count do
    receive do
      {:fetched, _} -> 1 + fetch_count()
    after
      0 -> 0
    end
  end

  test "verifies a delivery from a secure-mode server by signing the key fetch", ctx do
    serve_actor(ctx.actor, ctx.key_id, ctx.public_pem)

    assert {:ok, key_id} = HTTPSignature.verify(signed_post(ctx.private_pem, ctx.key_id))
    assert key_id == ctx.key_id
    # The key fetch carried our signature (a secure-mode server demands it).
    assert_received {:fetched, [signature]}
    assert signature =~ ~s(keyId="#{Hybridsocial.Federation.InstanceActor.ap_id()}#main-key")
  end

  test "caches the key: a second delivery doesn't refetch", ctx do
    serve_actor(ctx.actor, ctx.key_id, ctx.public_pem)

    assert {:ok, _} = HTTPSignature.verify(signed_post(ctx.private_pem, ctx.key_id))
    assert {:ok, _} = HTTPSignature.verify(signed_post(ctx.private_pem, ctx.key_id))
    assert fetch_count() == 1
  end

  test "a rotated key is picked up: a stale cached key triggers one refetch", ctx do
    {_old_priv, old_pub} = keypair()
    Hybridsocial.Cache.set("httpsig:key:" <> ctx.key_id, old_pub, 3600)
    serve_actor(ctx.actor, ctx.key_id, ctx.public_pem)

    assert {:ok, _} = HTTPSignature.verify(signed_post(ctx.private_pem, ctx.key_id))
    assert fetch_count() == 1
  end

  test "a forged signature is rejected, with at most one refetch", ctx do
    {forger_priv, _} = keypair()
    serve_actor(ctx.actor, ctx.key_id, ctx.public_pem)

    assert {:error, :invalid_signature} =
             HTTPSignature.verify(signed_post(forger_priv, ctx.key_id))

    # The key is now cached: a second forgery costs a refetch, not more.
    assert {:error, :invalid_signature} =
             HTTPSignature.verify(signed_post(forger_priv, ctx.key_id))

    assert fetch_count() <= 2
  end

  test "rejects a key published under a different id than the keyId", ctx do
    serve_actor(ctx.actor, ctx.actor <> "#other-key", ctx.public_pem)

    assert {:error, :invalid_actor} =
             HTTPSignature.verify(signed_post(ctx.private_pem, ctx.key_id))
  end

  test "rejects a POST whose signature doesn't cover digest", ctx do
    serve_actor(ctx.actor, ctx.key_id, ctx.public_pem)
    conn = signed_post(ctx.private_pem, ctx.key_id)
    [sig] = Plug.Conn.get_req_header(conn, "signature")
    stripped = String.replace(sig, ~r{headers="[^"]*"}, ~s{headers="(request-target) host date"})
    conn = Plug.Conn.put_req_header(conn, "signature", stripped)

    assert {:error, :digest_not_signed} = HTTPSignature.verify(conn)
  end

  test "malformed signature bytes are a rejection, not a crash", ctx do
    serve_actor(ctx.actor, ctx.key_id, ctx.public_pem)
    conn = signed_post(ctx.private_pem, ctx.key_id)
    [sig] = Plug.Conn.get_req_header(conn, "signature")
    broken = String.replace(sig, ~r{signature="[^"]*"}, ~s{signature="%%%not-base64%%%"})
    conn = Plug.Conn.put_req_header(conn, "signature", broken)

    assert {:error, :invalid_signature} = HTTPSignature.verify(conn)
  end
end
