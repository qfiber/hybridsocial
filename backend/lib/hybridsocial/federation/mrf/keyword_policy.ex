defmodule Hybridsocial.Federation.MRF.KeywordPolicy do
  @moduledoc """
  Rejects or replaces content based on keyword matching.

  Reads keyword lists from Config:
  - `mrf_keyword_reject`: list of patterns that cause rejection
  - `mrf_keyword_replace`: list of `{pattern, replacement}` tuples
  """
  @behaviour Hybridsocial.Federation.MRF.Policy

  alias Hybridsocial.Config

  @impl true
  def filter(%{"type" => "Create", "object" => %{"content" => content}} = activity)
      when is_binary(content) do
    reject_patterns = Config.get("mrf_keyword_reject", [])
    replace_patterns = Config.get("mrf_keyword_replace", [])

    case check_reject(content, reject_patterns) do
      {:reject, reason} ->
        {:reject, reason}

      :ok ->
        new_content = apply_replacements(content, replace_patterns)
        {:ok, put_in(activity, ["object", "content"], new_content)}
    end
  end

  def filter(activity), do: {:ok, activity}

  @impl true
  def describe do
    {:ok, %{name: "keyword", description: "Reject or replace content by keyword."}}
  end

  defp check_reject(_content, []), do: :ok

  defp check_reject(content, [pattern | rest]) when is_binary(pattern) do
    if String.contains?(String.downcase(content), String.downcase(pattern)) do
      {:reject, "Keyword filter: matched '#{pattern}'"}
    else
      check_reject(content, rest)
    end
  end

  defp check_reject(content, [_ | rest]), do: check_reject(content, rest)

  defp apply_replacements(content, []), do: content

  defp apply_replacements(content, [%{"pattern" => pattern, "replacement" => replacement} | rest])
       when is_binary(pattern) and is_binary(replacement) do
    content
    |> String.replace(pattern, replacement)
    |> apply_replacements(rest)
  end

  defp apply_replacements(content, [_ | rest]), do: apply_replacements(content, rest)
end
