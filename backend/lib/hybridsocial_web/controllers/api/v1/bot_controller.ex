defmodule HybridsocialWeb.Api.V1.BotController do
  use HybridsocialWeb, :controller

  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts.{Identity, Bot}
  alias Hybridsocial.Auth.{OAuth, OAuthApplication, OAuthToken, Token}

  @doc "List current user's bots with their OAuth apps."
  def index(conn, _params) do
    identity = conn.assigns.current_identity

    bots =
      Identity
      |> where([i], i.parent_identity_id == ^identity.id and i.type == "bot")
      |> where([i], is_nil(i.deleted_at))
      |> order_by([i], desc: i.inserted_at)
      |> Repo.all()
      |> Repo.preload(:bot)

    bot_data =
      Enum.map(bots, fn bot_identity ->
        apps = OAuth.list_applications(bot_identity.id)

        %{
          id: bot_identity.id,
          name: bot_identity.display_name,
          handle: bot_identity.handle,
          created_at: bot_identity.inserted_at,
          apps:
            Enum.map(apps, fn app ->
              %{
                id: app.id,
                name: app.name,
                client_id: app.client_id,
                scopes: app.scopes,
                created_at: app.inserted_at
              }
            end)
        }
      end)

    json(conn, bot_data)
  end

  @doc "Create a bot with an OAuth app and token in one step."
  def create(conn, params) do
    identity = conn.assigns.current_identity
    name = params["name"] || ""
    handle = params["handle"] || generate_bot_handle(name)

    Repo.transaction(fn ->
      # 1. Create bot identity
      identity_attrs = %{
        type: "bot",
        handle: handle,
        display_name: name,
        is_bot: true,
        parent_identity_id: identity.id
      }

      case %Identity{} |> Identity.create_changeset(identity_attrs) |> Repo.insert() do
        {:ok, bot_identity} ->
          # 2. Create bot record
          case %Bot{identity_id: bot_identity.id}
               |> Bot.changeset(%{is_active: true})
               |> Repo.insert() do
            {:ok, _bot} ->
              # 3. Create OAuth app linked to the bot identity
              app_attrs = %{
                "name" => "#{name} API",
                "redirect_uris" => ["urn:ietf:wg:oauth:2.0:oob"],
                "scopes" => ["read", "write", "follow", "push"]
              }

              case OAuth.create_application(app_attrs, bot_identity.id) do
                {:ok, app, client_secret} ->
                  # 4. Generate access token for the bot
                  case generate_bot_token(bot_identity.id, app.id) do
                    {:ok, access_token} ->
                      %{
                        bot: %{
                          id: bot_identity.id,
                          name: bot_identity.display_name,
                          handle: bot_identity.handle
                        },
                        client_id: app.client_id,
                        client_secret: client_secret,
                        access_token: access_token,
                        note:
                          "Save these credentials now. The client secret and access token will not be shown again."
                      }

                    {:error, reason} ->
                      Repo.rollback(reason)
                  end

                {:error, changeset} ->
                  Repo.rollback(changeset)
              end

            {:error, changeset} ->
              Repo.rollback(changeset)
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, result} ->
        conn
        |> put_status(:created)
        |> json(result)

      {:error, changeset} when is_map(changeset) ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "bot.creation_failed", details: inspect(reason)})
    end
  end

  @doc "Delete a bot and all its OAuth apps/tokens."
  def delete(conn, %{"id" => bot_id}) do
    identity = conn.assigns.current_identity

    # Verify the bot belongs to current user
    case Repo.get(Identity, bot_id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "bot.not_found"})

      bot_identity ->
        if bot_identity.parent_identity_id != identity.id or bot_identity.type != "bot" do
          conn |> put_status(:forbidden) |> json(%{error: "bot.not_owner"})
        else
          Repo.transaction(fn ->
            # Delete OAuth tokens for this bot identity
            OAuthToken
            |> where([t], t.identity_id == ^bot_id)
            |> Repo.delete_all()

            # Delete OAuth apps created by this bot identity
            OAuthApplication
            |> where([a], a.created_by == ^bot_id)
            |> Repo.delete_all()

            # Delete the bot record
            case Repo.get(Bot, bot_id) do
              nil -> :ok
              bot -> Repo.delete(bot)
            end

            # Soft-delete the identity
            bot_identity
            |> Identity.soft_delete_changeset()
            |> Repo.update!()
          end)

          send_resp(conn, :no_content, "")
        end
    end
  end

  @doc "Regenerate API keys for a bot."
  def regenerate(conn, %{"id" => bot_id}) do
    identity = conn.assigns.current_identity

    case Repo.get(Identity, bot_id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "bot.not_found"})

      bot_identity ->
        if bot_identity.parent_identity_id != identity.id or bot_identity.type != "bot" do
          conn |> put_status(:forbidden) |> json(%{error: "bot.not_owner"})
        else
          Repo.transaction(fn ->
            # Revoke all existing tokens
            OAuthToken
            |> where([t], t.identity_id == ^bot_id)
            |> Repo.delete_all()

            # Delete old OAuth apps
            OAuthApplication
            |> where([a], a.created_by == ^bot_id)
            |> Repo.delete_all()

            # Create new OAuth app
            app_attrs = %{
              "name" => "#{bot_identity.display_name} API",
              "redirect_uris" => ["urn:ietf:wg:oauth:2.0:oob"],
              "scopes" => ["read", "write", "follow", "push"]
            }

            case OAuth.create_application(app_attrs, bot_id) do
              {:ok, app, client_secret} ->
                case generate_bot_token(bot_id, app.id) do
                  {:ok, access_token} ->
                    %{
                      client_id: app.client_id,
                      client_secret: client_secret,
                      access_token: access_token,
                      note:
                        "Save these credentials now. The client secret and access token will not be shown again."
                    }

                  {:error, reason} ->
                    Repo.rollback(reason)
                end

              {:error, changeset} ->
                Repo.rollback(changeset)
            end
          end)
          |> case do
            {:ok, result} ->
              json(conn, result)

            {:error, reason} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "bot.regenerate_failed", details: inspect(reason)})
          end
        end
    end
  end

  # --- Private helpers ---

  defp generate_bot_handle(name) do
    base =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9_]/, "")
      |> String.slice(0, 10)
      |> case do
        "" -> "bot"
        s -> s
      end

    suffix = :crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)
    "#{base}_bot_#{suffix}"
  end

  defp generate_bot_token(identity_id, application_id) do
    with {:ok, access_token, _claims} <- Token.generate_access_token(identity_id) do
      token_hash = Token.hash_token(access_token)
      expires_at = DateTime.add(DateTime.utc_now(), 365 * 24 * 3600, :second)

      case %OAuthToken{}
           |> OAuthToken.changeset(%{
             identity_id: identity_id,
             application_id: application_id,
             token_hash: token_hash,
             refresh_token_hash: Token.hash_token(:crypto.strong_rand_bytes(64) |> Base.url_encode64(padding: false)),
             scopes: ["read", "write", "follow", "push"],
             expires_at: expires_at
           })
           |> Repo.insert() do
        {:ok, _} -> {:ok, access_token}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  defp format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp format_errors(other), do: %{base: [inspect(other)]}
end
