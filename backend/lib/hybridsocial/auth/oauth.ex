defmodule Hybridsocial.Auth.OAuth do
  @moduledoc """
  OAuth2 provider context. Handles app registration, authorization codes (PKCE),
  and token exchange.
  """
  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Auth.{OAuthApplication, OAuthToken, AuthorizationCode, Token}

  # 10 minutes in seconds
  @authorization_code_ttl 600

  # --- Application management ---

  def create_application(attrs, creator_identity_id) do
    do_create_application(attrs, creator_identity_id)
  end

  defp do_create_application(attrs, creator_identity_id) do
    client_id = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    client_secret = :crypto.strong_rand_bytes(64) |> Base.url_encode64(padding: false)
    secret_hash = :crypto.hash(:sha256, client_secret) |> Base.encode16(case: :lower)

    result =
      %OAuthApplication{}
      |> Ecto.Changeset.change(%{
        name: attrs["name"] || attrs[:name],
        redirect_uris: attrs["redirect_uris"] || attrs[:redirect_uris] || [],
        scopes: attrs["scopes"] || attrs[:scopes] || [],
        website: attrs["website"] || attrs[:website],
        client_id: client_id,
        client_secret_hash: secret_hash,
        created_by: creator_identity_id
      })
      |> Ecto.Changeset.validate_required([:name, :client_id, :client_secret_hash])
      |> Repo.insert()

    case result do
      {:ok, app} ->
        {:ok, app, client_secret}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def get_application(id) do
    Repo.get(OAuthApplication, id)
  end

  def get_application_by_client_id(client_id) do
    OAuthApplication
    |> where([a], a.client_id == ^client_id)
    |> Repo.one()
  end

  def list_applications(identity_id) do
    OAuthApplication
    |> where([a], a.created_by == ^identity_id)
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  def delete_application(id, identity_id) do
    case get_application(id) do
      nil ->
        {:error, :not_found}

      app ->
        if app.created_by == identity_id do
          Repo.delete(app)
        else
          {:error, :unauthorized}
        end
    end
  end

  def verify_client_credentials(client_id, client_secret) do
    case get_application_by_client_id(client_id) do
      nil ->
        {:error, :invalid_client}

      app ->
        secret_hash = :crypto.hash(:sha256, client_secret) |> Base.encode16(case: :lower)

        if Plug.Crypto.secure_compare(secret_hash, app.client_secret_hash) do
          {:ok, app}
        else
          {:error, :invalid_client}
        end
    end
  end

  # --- Authorization codes (PKCE) ---

  def create_authorization_code(identity_id, application_id, scopes, redirect_uri, code_challenge) do
    code = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    code_hash = hash_code(code)
    expires_at = DateTime.add(DateTime.utc_now(), @authorization_code_ttl, :second)

    result =
      %AuthorizationCode{}
      |> AuthorizationCode.changeset(%{
        code_hash: code_hash,
        application_id: application_id,
        identity_id: identity_id,
        redirect_uri: redirect_uri,
        scopes: scopes || [],
        code_challenge: code_challenge,
        code_challenge_method: "S256",
        expires_at: expires_at,
        inserted_at: DateTime.utc_now()
      })
      |> Repo.insert()

    case result do
      {:ok, _auth_code} -> {:ok, code}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def exchange_code(code, code_verifier, client_id, redirect_uri) do
    code_hash = hash_code(code)

    with {:ok, auth_code} <- get_valid_authorization_code(code_hash),
         {:ok, _app} <- verify_client_id(auth_code, client_id),
         :ok <- verify_redirect_uri(auth_code, redirect_uri),
         :ok <- verify_code_challenge(auth_code, code_verifier),
         {:ok, _} <- delete_authorization_code(auth_code) do
      create_oauth_tokens(auth_code.identity_id, auth_code.application_id, auth_code.scopes)
    end
  end

  def revoke_token(token) do
    token_hash = Token.hash_token(token)

    case get_active_token_by_hash(token_hash) do
      nil ->
        # Also try by refresh token hash
        case get_active_token_by_refresh_hash(token_hash) do
          nil -> {:ok, :already_revoked}
          oauth_token -> do_revoke_token(oauth_token)
        end

      oauth_token ->
        do_revoke_token(oauth_token)
    end
  end

  # --- Private helpers ---

  defp hash_code(code) do
    :crypto.hash(:sha256, code) |> Base.encode16(case: :lower)
  end

  defp get_valid_authorization_code(code_hash) do
    now = DateTime.utc_now()

    case Repo.get(AuthorizationCode, code_hash) do
      nil ->
        {:error, :invalid_code}

      auth_code ->
        if DateTime.compare(auth_code.expires_at, now) == :gt do
          {:ok, auth_code}
        else
          # Clean up expired code
          Repo.delete(auth_code)
          {:error, :code_expired}
        end
    end
  end

  defp verify_client_id(auth_code, client_id) do
    app = Repo.get(OAuthApplication, auth_code.application_id)

    if app && app.client_id == client_id do
      {:ok, app}
    else
      {:error, :invalid_client}
    end
  end

  defp verify_redirect_uri(auth_code, redirect_uri) do
    if auth_code.redirect_uri == redirect_uri do
      :ok
    else
      {:error, :redirect_uri_mismatch}
    end
  end

  defp verify_code_challenge(auth_code, code_verifier) do
    expected_challenge = auth_code.code_challenge

    computed_challenge =
      :crypto.hash(:sha256, code_verifier)
      |> Base.url_encode64(padding: false)

    if Plug.Crypto.secure_compare(computed_challenge, expected_challenge) do
      :ok
    else
      {:error, :invalid_code_verifier}
    end
  end

  defp delete_authorization_code(auth_code) do
    Repo.delete(auth_code)
  end

  defp create_oauth_tokens(identity_id, application_id, scopes) do
    with {:ok, access_token, _claims} <- Token.generate_access_token(identity_id),
         {refresh_token, refresh_hash} <- Token.generate_refresh_token() do
      token_hash = Token.hash_token(access_token)
      expires_at = DateTime.add(DateTime.utc_now(), Token.access_token_ttl(), :second)

      result =
        %OAuthToken{}
        |> OAuthToken.changeset(%{
          identity_id: identity_id,
          application_id: application_id,
          token_hash: token_hash,
          refresh_token_hash: refresh_hash,
          scopes: scopes,
          expires_at: expires_at
        })
        |> Repo.insert()

      case result do
        {:ok, _oauth_token} ->
          {:ok,
           %{
             access_token: access_token,
             refresh_token: refresh_token,
             token_type: "Bearer",
             expires_in: Token.access_token_ttl(),
             scope: Enum.join(scopes, " ")
           }}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  defp get_active_token_by_hash(token_hash) do
    OAuthToken
    |> where([t], t.token_hash == ^token_hash and is_nil(t.revoked_at))
    |> Repo.one()
  end

  defp get_active_token_by_refresh_hash(token_hash) do
    OAuthToken
    |> where([t], t.refresh_token_hash == ^token_hash and is_nil(t.revoked_at))
    |> Repo.one()
  end

  defp do_revoke_token(oauth_token) do
    oauth_token
    |> OAuthToken.revoke_changeset()
    |> Repo.update()
  end
end
