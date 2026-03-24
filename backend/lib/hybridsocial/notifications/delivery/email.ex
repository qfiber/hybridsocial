defmodule Hybridsocial.Notifications.Delivery.Email do
  @moduledoc """
  Email notification delivery channel.

  Composes and sends notification emails via `Hybridsocial.Mailer` using Swoosh.
  """

  @behaviour Hybridsocial.Notifications.Delivery

  import Swoosh.Email

  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts.Identity

  require Logger

  @impl true
  def deliver(recipient_id, payload, _opts) do
    case fetch_recipient_email(recipient_id) do
      {:ok, email_address} ->
        email =
          new()
          |> to(email_address)
          |> from({Hybridsocial.Config.instance_name(), from_address()})
          |> subject(payload.title)
          |> text_body(payload.body)
          |> html_body(render_html(payload))

        case Hybridsocial.Mailer.deliver(email) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.warning("Email notification delivery failed: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.debug("Skipping email notification: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def channel_name, do: :email

  @impl true
  def available? do
    config = Application.get_env(:hybridsocial, Hybridsocial.Mailer)
    config != nil and Keyword.get(config, :adapter) != nil
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp fetch_recipient_email(recipient_id) do
    identity =
      Identity
      |> Repo.get(recipient_id)
      |> Repo.preload(:user)

    case identity do
      %Identity{user: %{email: email}} when is_binary(email) and email != "" ->
        {:ok, email}

      _ ->
        {:error, :no_email}
    end
  end

  defp from_address do
    Hybridsocial.Config.get("notification_from_email", "notifications@localhost")
  end

  defp render_html(payload) do
    """
    <div style="font-family: sans-serif; max-width: 600px; margin: 0 auto;">
      <h2>#{html_escape(payload.title)}</h2>
      <p>#{html_escape(payload.body)}</p>
      <p><a href="#{html_escape(payload.data[:url] || "/notifications")}">View notification</a></p>
    </div>
    """
  end

  defp html_escape(nil), do: ""

  defp html_escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp html_escape(text), do: html_escape(to_string(text))
end
