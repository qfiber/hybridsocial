defmodule Hybridsocial.Auth.Turnstile do
  @moduledoc "Cloudflare Turnstile captcha verification."

  alias Hybridsocial.Config

  @verify_url "https://challenges.cloudflare.com/turnstile/v0/siteverify"

  def enabled? do
    secret = Config.get("turnstile_secret_key", "")
    secret != nil and secret != ""
  end

  def verify(token) when is_binary(token) do
    secret = Config.get("turnstile_secret_key", "")

    body = URI.encode_query(%{secret: secret, response: token})

    case HTTPoison.post(@verify_url, body, [{"Content-Type", "application/x-www-form-urlencoded"}]) do
      {:ok, %{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"success" => true}} -> {:ok, true}
          {:ok, %{"success" => false}} -> {:error, :captcha_failed}
          _ -> {:error, :captcha_parse_error}
        end

      _ ->
        {:error, :captcha_service_unavailable}
    end
  end

  def verify(_), do: {:error, :missing_token}
end
