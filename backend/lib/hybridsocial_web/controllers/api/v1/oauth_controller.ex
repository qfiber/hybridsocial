defmodule HybridsocialWeb.Api.V1.OAuthController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Auth.OAuth

  # --- App management (authenticated) ---

  def create_app(conn, params) do
    identity = conn.assigns.current_identity

    case OAuth.create_application(params, identity.id) do
      {:ok, app, client_secret} ->
        conn
        |> put_status(:created)
        |> json(%{
          id: app.id,
          name: app.name,
          client_id: app.client_id,
          client_secret: client_secret,
          redirect_uris: app.redirect_uris,
          scopes: app.scopes,
          website: app.website
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  def list_apps(conn, _params) do
    identity = conn.assigns.current_identity
    apps = OAuth.list_applications(identity.id)

    conn
    |> put_status(:ok)
    |> json(Enum.map(apps, &serialize_app/1))
  end

  def delete_app(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case OAuth.delete_application(id, identity.id) do
      {:ok, _app} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "oauth.app_deleted"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "oauth.app_not_found"})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "oauth.not_app_owner"})
    end
  end

  # --- Authorization (authenticated) ---

  def authorize(conn, params) do
    identity = conn.assigns.current_identity

    with {:ok, _} <- validate_response_type(params["response_type"]),
         {:ok, app} <- validate_client(params["client_id"]),
         :ok <- validate_redirect_uri(app, params["redirect_uri"]),
         {:ok, _} <- validate_code_challenge(params["code_challenge"]) do
      scopes = parse_scopes(params["scope"] || params["scopes"])

      case OAuth.create_authorization_code(
             identity.id,
             app.id,
             scopes,
             params["redirect_uri"],
             params["code_challenge"]
           ) do
        {:ok, code} ->
          conn
          |> put_status(:ok)
          |> json(%{code: code, redirect_uri: params["redirect_uri"]})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "oauth.authorization_failed", details: format_errors(changeset)})
      end
    else
      {:error, error_key} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: error_key})
    end
  end

  # --- Token exchange (public) ---

  def token(conn, %{"grant_type" => "authorization_code"} = params) do
    case OAuth.exchange_code(
           params["code"],
           params["code_verifier"],
           params["client_id"],
           params["redirect_uri"]
         ) do
      {:ok, tokens} ->
        conn
        |> put_status(:ok)
        |> json(tokens)

      {:error, reason} when is_atom(reason) ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: to_string(reason)})

      {:error, _changeset} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "oauth.token_creation_failed"})
    end
  end

  def token(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "oauth.unsupported_grant_type"})
  end

  # --- Token revocation (public) ---

  def revoke(conn, %{"token" => token_value}) do
    OAuth.revoke_token(token_value)

    # Per RFC 7009, always return 200 regardless of whether token existed
    conn
    |> put_status(:ok)
    |> json(%{})
  end

  def revoke(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "oauth.token_required"})
  end

  # --- Private helpers ---

  defp validate_response_type("code"), do: {:ok, :code}
  defp validate_response_type(_), do: {:error, "oauth.unsupported_response_type"}

  defp validate_client(nil), do: {:error, "oauth.client_id_required"}

  defp validate_client(client_id) do
    case OAuth.get_application_by_client_id(client_id) do
      nil -> {:error, "oauth.invalid_client_id"}
      app -> {:ok, app}
    end
  end

  defp validate_redirect_uri(app, redirect_uri) do
    if redirect_uri in app.redirect_uris do
      :ok
    else
      {:error, "oauth.invalid_redirect_uri"}
    end
  end

  defp validate_code_challenge(nil), do: {:error, "oauth.code_challenge_required"}
  defp validate_code_challenge(""), do: {:error, "oauth.code_challenge_required"}
  defp validate_code_challenge(_challenge), do: {:ok, :valid}

  defp parse_scopes(scopes) when is_list(scopes), do: scopes
  defp parse_scopes(scopes) when is_binary(scopes), do: String.split(scopes, " ", trim: true)
  defp parse_scopes(_), do: ["read"]

  defp serialize_app(app) do
    %{
      id: app.id,
      name: app.name,
      client_id: app.client_id,
      redirect_uris: app.redirect_uris,
      scopes: app.scopes,
      website: app.website,
      created_at: app.inserted_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
