defmodule Hybridsocial.Auth do
  @moduledoc """
  Authentication context. Handles login, token management, and session lifecycle.
  """
  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts
  alias Hybridsocial.Accounts.User
  alias Hybridsocial.Auth.Token
  alias Hybridsocial.Auth.OAuthToken

  def login(email, password) do
    with {:ok, user} <- Accounts.authenticate_user(email, password) do
      if user.otp_enabled do
        {:error, :otp_required, user.identity_id}
      else
        issue_tokens(user)
      end
    end
  end

  def login_with_otp(identity_id, code) do
    with {:ok, user} <- Accounts.verify_2fa(identity_id, code) do
      user = Repo.preload(user, :identity)
      issue_tokens(user)
    end
  end

  defp issue_tokens(user) do
    with {:ok, access_token, _claims} <- Token.generate_access_token(user.identity_id),
         {refresh_token, refresh_hash} <- Token.generate_refresh_token(),
         {:ok, _oauth_token} <- create_token_record(user.identity_id, access_token, refresh_hash) do
      # Update last login
      user |> User.login_changeset() |> Repo.update()

      {:ok,
       %{
         access_token: access_token,
         refresh_token: refresh_token,
         token_type: "Bearer",
         expires_in: Token.access_token_ttl(),
         identity_id: user.identity_id
       }}
    end
  end

  def refresh(refresh_token) do
    refresh_hash = Token.hash_token(refresh_token)

    case get_valid_token_by_refresh(refresh_hash) do
      nil ->
        {:error, :invalid_refresh_token}

      oauth_token ->
        # Revoke old token
        revoke_token(oauth_token)

        # Generate new pair
        with {:ok, access_token, _claims} <- Token.generate_access_token(oauth_token.identity_id),
             {new_refresh, new_refresh_hash} <- Token.generate_refresh_token(),
             {:ok, _} <- create_token_record(oauth_token.identity_id, access_token, new_refresh_hash) do
          {:ok,
           %{
             access_token: access_token,
             refresh_token: new_refresh,
             token_type: "Bearer",
             expires_in: Token.access_token_ttl(),
             identity_id: oauth_token.identity_id
           }}
        end
    end
  end

  def logout(access_token) do
    token_hash = Token.hash_token(access_token)

    case get_token_by_hash(token_hash) do
      nil -> {:ok, :logged_out}
      oauth_token -> revoke_token(oauth_token)
    end
  end

  defp create_token_record(identity_id, access_token, refresh_hash) do
    token_hash = Token.hash_token(access_token)
    expires_at = DateTime.add(DateTime.utc_now(), Token.access_token_ttl(), :second)

    %OAuthToken{}
    |> OAuthToken.changeset(%{
      identity_id: identity_id,
      token_hash: token_hash,
      refresh_token_hash: refresh_hash,
      scopes: ["read", "write"],
      expires_at: expires_at
    })
    |> Repo.insert()
  end

  defp get_valid_token_by_refresh(refresh_hash) do
    import Ecto.Query

    OAuthToken
    |> where([t], t.refresh_token_hash == ^refresh_hash and is_nil(t.revoked_at))
    |> Repo.one()
  end

  defp get_token_by_hash(token_hash) do
    import Ecto.Query

    OAuthToken
    |> where([t], t.token_hash == ^token_hash and is_nil(t.revoked_at))
    |> Repo.one()
  end

  defp revoke_token(oauth_token) do
    oauth_token
    |> OAuthToken.revoke_changeset()
    |> Repo.update()
  end
end
