defmodule HybridsocialWeb.Api.V1.OAuthControllerTest do
  use HybridsocialWeb.ConnCase, async: true

  alias Hybridsocial.Accounts
  alias Hybridsocial.Auth
  alias Hybridsocial.Auth.OAuth

  @user_attrs %{
    "handle" => "oauthtestuser",
    "display_name" => "OAuth Test User",
    "email" => "oauthtest@example.com",
    "password" => "password123",
    "password_confirmation" => "password123"
  }

  defp create_user_and_login(conn) do
    {:ok, identity} = Accounts.register_user(@user_attrs)
    {:ok, tokens} = Auth.login("oauthtest@example.com", "password123")

    authed_conn =
      conn
      |> put_req_header("authorization", "Bearer #{tokens.access_token}")

    {identity, authed_conn, tokens}
  end

  defp create_app(identity_id) do
    {:ok, app, _secret} =
      OAuth.create_application(
        %{"name" => "Test App", "redirect_uris" => ["https://example.com/callback"]},
        identity_id
      )

    app
  end

  defp generate_pkce do
    code_verifier = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    code_challenge =
      :crypto.hash(:sha256, code_verifier)
      |> Base.url_encode64(padding: false)

    {code_verifier, code_challenge}
  end

  describe "POST /api/v1/apps" do
    test "creates an app when authenticated", %{conn: conn} do
      {_identity, authed_conn, _tokens} = create_user_and_login(conn)

      resp =
        authed_conn
        |> post("/api/v1/apps", %{
          "name" => "My Cool App",
          "redirect_uris" => ["https://myapp.com/callback"],
          "website" => "https://myapp.com"
        })
        |> json_response(201)

      assert resp["name"] == "My Cool App"
      assert resp["client_id"] != nil
      assert resp["client_secret"] != nil
      assert resp["redirect_uris"] == ["https://myapp.com/callback"]
    end

    test "returns 401 when not authenticated", %{conn: conn} do
      conn
      |> post("/api/v1/apps", %{"name" => "My App"})
      |> json_response(401)
    end
  end

  describe "GET /api/v1/apps" do
    test "lists own apps", %{conn: conn} do
      {identity, authed_conn, _tokens} = create_user_and_login(conn)
      _app = create_app(identity.id)

      resp =
        authed_conn
        |> get("/api/v1/apps")
        |> json_response(200)

      assert length(resp) == 1
      assert hd(resp)["name"] == "Test App"
      # client_secret should NOT be in listing
      refute Map.has_key?(hd(resp), "client_secret")
    end
  end

  describe "DELETE /api/v1/apps/:id" do
    test "deletes own app", %{conn: conn} do
      {identity, authed_conn, _tokens} = create_user_and_login(conn)
      app = create_app(identity.id)

      resp =
        authed_conn
        |> delete("/api/v1/apps/#{app.id}")
        |> json_response(200)

      assert resp["message"] == "oauth.app_deleted"
    end

    test "returns 404 for nonexistent app", %{conn: conn} do
      {_identity, authed_conn, _tokens} = create_user_and_login(conn)

      authed_conn
      |> delete("/api/v1/apps/#{Ecto.UUID.generate()}")
      |> json_response(404)
    end
  end

  describe "POST /oauth/authorize" do
    test "creates authorization code with PKCE", %{conn: conn} do
      {identity, authed_conn, _tokens} = create_user_and_login(conn)
      app = create_app(identity.id)
      {_code_verifier, code_challenge} = generate_pkce()

      resp =
        authed_conn
        |> post("/oauth/authorize", %{
          "response_type" => "code",
          "client_id" => app.client_id,
          "redirect_uri" => "https://example.com/callback",
          "scope" => "read write",
          "code_challenge" => code_challenge
        })
        |> json_response(200)

      assert resp["code"] != nil
      assert resp["redirect_uri"] == "https://example.com/callback"
    end

    test "rejects invalid response_type", %{conn: conn} do
      {_identity, authed_conn, _tokens} = create_user_and_login(conn)

      resp =
        authed_conn
        |> post("/oauth/authorize", %{
          "response_type" => "token",
          "client_id" => "something",
          "redirect_uri" => "https://example.com/callback",
          "code_challenge" => "challenge"
        })
        |> json_response(400)

      assert resp["error"] == "oauth.unsupported_response_type"
    end

    test "rejects missing code_challenge", %{conn: conn} do
      {identity, authed_conn, _tokens} = create_user_and_login(conn)
      app = create_app(identity.id)

      resp =
        authed_conn
        |> post("/oauth/authorize", %{
          "response_type" => "code",
          "client_id" => app.client_id,
          "redirect_uri" => "https://example.com/callback"
        })
        |> json_response(400)

      assert resp["error"] == "oauth.code_challenge_required"
    end

    test "rejects invalid redirect_uri", %{conn: conn} do
      {identity, authed_conn, _tokens} = create_user_and_login(conn)
      app = create_app(identity.id)
      {_code_verifier, code_challenge} = generate_pkce()

      resp =
        authed_conn
        |> post("/oauth/authorize", %{
          "response_type" => "code",
          "client_id" => app.client_id,
          "redirect_uri" => "https://evil.com/callback",
          "code_challenge" => code_challenge
        })
        |> json_response(400)

      assert resp["error"] == "oauth.invalid_redirect_uri"
    end

    test "returns 401 when not authenticated", %{conn: conn} do
      conn
      |> post("/oauth/authorize", %{})
      |> json_response(401)
    end
  end

  describe "POST /oauth/token" do
    test "exchanges code for tokens with valid PKCE", %{conn: conn} do
      {identity, authed_conn, _tokens} = create_user_and_login(conn)
      app = create_app(identity.id)
      {code_verifier, code_challenge} = generate_pkce()

      # Get authorization code
      auth_resp =
        authed_conn
        |> post("/oauth/authorize", %{
          "response_type" => "code",
          "client_id" => app.client_id,
          "redirect_uri" => "https://example.com/callback",
          "scope" => "read write",
          "code_challenge" => code_challenge
        })
        |> json_response(200)

      # Exchange code for tokens (public endpoint)
      token_resp =
        conn
        |> post("/oauth/token", %{
          "grant_type" => "authorization_code",
          "code" => auth_resp["code"],
          "code_verifier" => code_verifier,
          "client_id" => app.client_id,
          "redirect_uri" => "https://example.com/callback"
        })
        |> json_response(200)

      assert token_resp["access_token"] != nil
      assert token_resp["refresh_token"] != nil
      assert token_resp["token_type"] == "Bearer"
      assert token_resp["expires_in"] > 0
    end

    test "rejects invalid code_verifier", %{conn: conn} do
      {identity, authed_conn, _tokens} = create_user_and_login(conn)
      app = create_app(identity.id)
      {_code_verifier, code_challenge} = generate_pkce()

      auth_resp =
        authed_conn
        |> post("/oauth/authorize", %{
          "response_type" => "code",
          "client_id" => app.client_id,
          "redirect_uri" => "https://example.com/callback",
          "scope" => "read",
          "code_challenge" => code_challenge
        })
        |> json_response(200)

      resp =
        conn
        |> post("/oauth/token", %{
          "grant_type" => "authorization_code",
          "code" => auth_resp["code"],
          "code_verifier" => "wrong_verifier",
          "client_id" => app.client_id,
          "redirect_uri" => "https://example.com/callback"
        })
        |> json_response(400)

      assert resp["error"] == "invalid_code_verifier"
    end

    test "rejects unsupported grant_type", %{conn: conn} do
      resp =
        conn
        |> post("/oauth/token", %{"grant_type" => "password"})
        |> json_response(400)

      assert resp["error"] == "oauth.unsupported_grant_type"
    end
  end

  describe "POST /oauth/revoke" do
    test "revokes a token", %{conn: conn} do
      {identity, authed_conn, _tokens} = create_user_and_login(conn)
      app = create_app(identity.id)
      {code_verifier, code_challenge} = generate_pkce()

      auth_resp =
        authed_conn
        |> post("/oauth/authorize", %{
          "response_type" => "code",
          "client_id" => app.client_id,
          "redirect_uri" => "https://example.com/callback",
          "scope" => "read",
          "code_challenge" => code_challenge
        })
        |> json_response(200)

      token_resp =
        conn
        |> post("/oauth/token", %{
          "grant_type" => "authorization_code",
          "code" => auth_resp["code"],
          "code_verifier" => code_verifier,
          "client_id" => app.client_id,
          "redirect_uri" => "https://example.com/callback"
        })
        |> json_response(200)

      # Revoke the access token
      resp =
        conn
        |> post("/oauth/revoke", %{"token" => token_resp["access_token"]})
        |> json_response(200)

      assert resp == %{}
    end

    test "returns 200 even for nonexistent token (RFC 7009)", %{conn: conn} do
      resp =
        conn
        |> post("/oauth/revoke", %{"token" => "nonexistent_token"})
        |> json_response(200)

      assert resp == %{}
    end

    test "returns error when token param missing", %{conn: conn} do
      resp =
        conn
        |> post("/oauth/revoke", %{})
        |> json_response(400)

      assert resp["error"] == "oauth.token_required"
    end
  end
end
