defmodule Hybridsocial.Auth.OAuthTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Auth.OAuth
  alias Hybridsocial.Accounts

  @user_attrs %{
    "handle" => "oauthuser",
    "display_name" => "OAuth User",
    "email" => "oauth@example.com",
    "password" => "password123",
    "password_confirmation" => "password123"
  }

  defp create_user do
    {:ok, identity} = Accounts.register_user(@user_attrs)
    identity
  end

  defp create_app(identity_id) do
    {:ok, app, _secret} =
      OAuth.create_application(%{"name" => "Test App", "redirect_uris" => ["https://example.com/callback"]}, identity_id)

    app
  end

  defp generate_pkce do
    code_verifier = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    code_challenge =
      :crypto.hash(:sha256, code_verifier)
      |> Base.url_encode64(padding: false)

    {code_verifier, code_challenge}
  end

  describe "create_application/2" do
    test "creates an application with generated credentials" do
      identity = create_user()
      {:ok, app, client_secret} = OAuth.create_application(%{"name" => "My App"}, identity.id)

      assert app.name == "My App"
      assert app.client_id != nil
      assert app.client_secret_hash != nil
      assert client_secret != nil
      assert app.created_by == identity.id
    end

    test "returns error without name" do
      identity = create_user()
      {:error, changeset} = OAuth.create_application(%{}, identity.id)

      assert errors_on(changeset) |> Map.has_key?(:name)
    end
  end

  describe "get_application/1" do
    test "returns the application by id" do
      identity = create_user()
      app = create_app(identity.id)

      assert OAuth.get_application(app.id).id == app.id
    end

    test "returns nil for nonexistent id" do
      assert OAuth.get_application(Ecto.UUID.generate()) == nil
    end
  end

  describe "get_application_by_client_id/1" do
    test "returns the application by client_id" do
      identity = create_user()
      app = create_app(identity.id)

      assert OAuth.get_application_by_client_id(app.client_id).id == app.id
    end
  end

  describe "list_applications/1" do
    test "returns applications for the given identity" do
      identity = create_user()
      _app1 = create_app(identity.id)
      _app2 = create_app(identity.id)

      apps = OAuth.list_applications(identity.id)
      assert length(apps) == 2
    end

    test "does not return apps from other identities" do
      identity = create_user()
      _app = create_app(identity.id)

      other_user_attrs = %{
        "handle" => "other",
        "display_name" => "Other",
        "email" => "other@example.com",
        "password" => "password123",
        "password_confirmation" => "password123"
      }

      {:ok, other} = Accounts.register_user(other_user_attrs)

      assert OAuth.list_applications(other.id) == []
    end
  end

  describe "delete_application/2" do
    test "deletes own application" do
      identity = create_user()
      app = create_app(identity.id)

      assert {:ok, _} = OAuth.delete_application(app.id, identity.id)
      assert OAuth.get_application(app.id) == nil
    end

    test "refuses to delete another user's app" do
      identity = create_user()
      app = create_app(identity.id)

      assert {:error, :unauthorized} = OAuth.delete_application(app.id, Ecto.UUID.generate())
    end

    test "returns not_found for nonexistent app" do
      assert {:error, :not_found} = OAuth.delete_application(Ecto.UUID.generate(), Ecto.UUID.generate())
    end
  end

  describe "verify_client_credentials/2" do
    test "verifies valid credentials" do
      identity = create_user()
      {:ok, app, client_secret} = OAuth.create_application(%{"name" => "My App"}, identity.id)

      assert {:ok, verified_app} = OAuth.verify_client_credentials(app.client_id, client_secret)
      assert verified_app.id == app.id
    end

    test "rejects invalid secret" do
      identity = create_user()
      {:ok, app, _} = OAuth.create_application(%{"name" => "My App"}, identity.id)

      assert {:error, :invalid_client} = OAuth.verify_client_credentials(app.client_id, "wrong_secret")
    end

    test "rejects invalid client_id" do
      assert {:error, :invalid_client} = OAuth.verify_client_credentials("nonexistent", "secret")
    end
  end

  describe "PKCE authorization code flow" do
    test "full flow: create code, exchange for tokens" do
      identity = create_user()
      app = create_app(identity.id)
      {code_verifier, code_challenge} = generate_pkce()

      {:ok, code} =
        OAuth.create_authorization_code(
          identity.id,
          app.id,
          ["read", "write"],
          "https://example.com/callback",
          code_challenge
        )

      assert is_binary(code)

      {:ok, tokens} =
        OAuth.exchange_code(code, code_verifier, app.client_id, "https://example.com/callback")

      assert tokens.access_token != nil
      assert tokens.refresh_token != nil
      assert tokens.token_type == "Bearer"
      assert tokens.expires_in > 0
    end

    test "rejects invalid code_verifier" do
      identity = create_user()
      app = create_app(identity.id)
      {_code_verifier, code_challenge} = generate_pkce()

      {:ok, code} =
        OAuth.create_authorization_code(
          identity.id,
          app.id,
          ["read"],
          "https://example.com/callback",
          code_challenge
        )

      assert {:error, :invalid_code_verifier} =
               OAuth.exchange_code(code, "wrong_verifier", app.client_id, "https://example.com/callback")
    end

    test "rejects invalid code" do
      identity = create_user()
      app = create_app(identity.id)

      assert {:error, :invalid_code} =
               OAuth.exchange_code("invalid_code", "verifier", app.client_id, "https://example.com/callback")
    end

    test "rejects mismatched redirect_uri" do
      identity = create_user()
      app = create_app(identity.id)
      {code_verifier, code_challenge} = generate_pkce()

      {:ok, code} =
        OAuth.create_authorization_code(
          identity.id,
          app.id,
          ["read"],
          "https://example.com/callback",
          code_challenge
        )

      assert {:error, :redirect_uri_mismatch} =
               OAuth.exchange_code(code, code_verifier, app.client_id, "https://evil.com/callback")
    end

    test "rejects mismatched client_id" do
      identity = create_user()
      app = create_app(identity.id)
      {code_verifier, code_challenge} = generate_pkce()

      {:ok, code} =
        OAuth.create_authorization_code(
          identity.id,
          app.id,
          ["read"],
          "https://example.com/callback",
          code_challenge
        )

      assert {:error, :invalid_client} =
               OAuth.exchange_code(code, code_verifier, "wrong_client_id", "https://example.com/callback")
    end

    test "code can only be used once" do
      identity = create_user()
      app = create_app(identity.id)
      {code_verifier, code_challenge} = generate_pkce()

      {:ok, code} =
        OAuth.create_authorization_code(
          identity.id,
          app.id,
          ["read"],
          "https://example.com/callback",
          code_challenge
        )

      assert {:ok, _tokens} =
               OAuth.exchange_code(code, code_verifier, app.client_id, "https://example.com/callback")

      assert {:error, :invalid_code} =
               OAuth.exchange_code(code, code_verifier, app.client_id, "https://example.com/callback")
    end
  end

  describe "revoke_token/1" do
    test "revokes an access token" do
      identity = create_user()
      app = create_app(identity.id)
      {code_verifier, code_challenge} = generate_pkce()

      {:ok, code} =
        OAuth.create_authorization_code(
          identity.id,
          app.id,
          ["read"],
          "https://example.com/callback",
          code_challenge
        )

      {:ok, tokens} =
        OAuth.exchange_code(code, code_verifier, app.client_id, "https://example.com/callback")

      assert {:ok, _} = OAuth.revoke_token(tokens.access_token)
    end

    test "returns ok for already revoked token" do
      assert {:ok, :already_revoked} = OAuth.revoke_token("nonexistent_token")
    end
  end
end
