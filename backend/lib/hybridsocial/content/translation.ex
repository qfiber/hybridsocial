defmodule Hybridsocial.Content.Translation do
  @moduledoc """
  Post translation service. Supports configurable translation backends.
  Default: LibreTranslate (free, self-hostable).
  """

  require Logger

  def translate(text, target_lang, source_lang \\ "auto") do
    backend = Hybridsocial.Config.get("translation_backend", "none")

    case backend do
      "libretranslate" -> translate_libre(text, target_lang, source_lang)
      "deepl" -> translate_deepl(text, target_lang, source_lang)
      _ -> {:error, :translation_disabled}
    end
  end

  def enabled? do
    Hybridsocial.Config.get("translation_backend", "none") != "none"
  end

  defp translate_libre(text, target, source) do
    url = Hybridsocial.Config.get("translation_api_url", "https://libretranslate.com")
    api_key = Hybridsocial.Config.get("translation_api_key", "")

    body = Jason.encode!(%{
      q: text,
      source: source,
      target: target,
      api_key: api_key
    })

    case HTTPoison.post("#{url}/translate", body, [{"Content-Type", "application/json"}], recv_timeout: 10_000) do
      {:ok, %{status_code: 200, body: resp}} ->
        case Jason.decode(resp) do
          {:ok, %{"translatedText" => translated}} -> {:ok, translated}
          _ -> {:error, :parse_error}
        end
      {:ok, %{status_code: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp translate_deepl(text, target, _source) do
    api_key = Hybridsocial.Config.get("translation_api_key", "")
    url = "https://api-free.deepl.com/v2/translate"

    body = URI.encode_query(%{
      "text" => text,
      "target_lang" => String.upcase(target),
      "auth_key" => api_key
    })

    case HTTPoison.post(url, body, [{"Content-Type", "application/x-www-form-urlencoded"}], recv_timeout: 10_000) do
      {:ok, %{status_code: 200, body: resp}} ->
        case Jason.decode(resp) do
          {:ok, %{"translations" => [%{"text" => translated} | _]}} -> {:ok, translated}
          _ -> {:error, :parse_error}
        end
      {:ok, %{status_code: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
