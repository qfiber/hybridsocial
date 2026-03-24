defmodule Hybridsocial.Moderation.Filters.CustomEngine do
  @moduledoc """
  Webhook-based content filter engine.

  First runs the default database filter engine. If content passes, sends it
  to a configurable webhook URL for external filtering. Falls back to the
  default engine result if the webhook is not configured or fails.

  The webhook receives a JSON POST:

      {"text": "...", "context": "posts"}

  And must respond with JSON:

      {"action": "ok", "text": "..."}       # content is acceptable
      {"action": "reject", "reason": "..."}  # content is rejected
      {"action": "flag", "reason": "..."}    # content is flagged
  """

  @behaviour Hybridsocial.Moderation.ContentFilterEngine

  require Logger

  alias Hybridsocial.Moderation.Filters.DefaultEngine

  @impl true
  def name, do: "custom"

  @impl true
  def configurable?, do: true

  @impl true
  def check(text, context \\ %{}) do
    case DefaultEngine.check(text, context) do
      {:ok, filtered_text} ->
        check_webhook(filtered_text, context)

      other ->
        other
    end
  end

  defp check_webhook(text, context) do
    case Hybridsocial.Config.get("content_filter_webhook_url") do
      nil ->
        {:ok, text}

      "" ->
        {:ok, text}

      url ->
        call_webhook(url, text, context)
    end
  end

  defp call_webhook(url, text, context) do
    filter_context = Map.get(context, :context, "all")

    body =
      Jason.encode!(%{
        text: text,
        context: filter_context
      })

    headers = [
      {"content-type", "application/json"},
      {"accept", "application/json"}
    ]

    case HTTPoison.post(url, body, headers, recv_timeout: 5_000, timeout: 5_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        parse_webhook_response(response_body, text)

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.warning(
          "Content filter webhook returned non-200 status: #{status}, falling back to default"
        )

        {:ok, text}

      {:error, reason} ->
        Logger.warning(
          "Content filter webhook request failed: #{inspect(reason)}, falling back to default"
        )

        {:ok, text}
    end
  end

  defp parse_webhook_response(body, original_text) do
    case Jason.decode(body) do
      {:ok, %{"action" => "reject", "reason" => reason}} ->
        {:reject, reason}

      {:ok, %{"action" => "flag", "reason" => reason}} ->
        {:flag, reason}

      {:ok, %{"action" => "ok", "text" => text}} ->
        {:ok, text}

      {:ok, %{"action" => "ok"}} ->
        {:ok, original_text}

      {:ok, other} ->
        Logger.warning(
          "Content filter webhook returned unexpected payload: #{inspect(other)}, falling back to default"
        )

        {:ok, original_text}

      {:error, reason} ->
        Logger.warning(
          "Content filter webhook returned invalid JSON: #{inspect(reason)}, falling back to default"
        )

        {:ok, original_text}
    end
  end
end
