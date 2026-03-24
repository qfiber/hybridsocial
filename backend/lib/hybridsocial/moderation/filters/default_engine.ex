defmodule Hybridsocial.Moderation.Filters.DefaultEngine do
  @moduledoc """
  Default content filter engine backed by database filter rules.

  Loads all `ContentFilter` records from the database and applies them
  sequentially. Filters can be scoped by context (posts, usernames, bios, all).
  """

  @behaviour Hybridsocial.Moderation.ContentFilterEngine

  require Logger

  alias Hybridsocial.Moderation
  alias Hybridsocial.Moderation.ContentFilter

  @impl true
  def name, do: "default"

  @impl true
  def configurable?, do: true

  @impl true
  def check(text, context \\ %{}) do
    filter_context = Map.get(context, :context, "all")

    filters =
      Moderation.list_filters()
      |> Enum.filter(&matches_context?(&1, filter_context))

    do_check(text, filters)
  end

  defp matches_context?(%ContentFilter{context: "all"}, _requested), do: true
  defp matches_context?(%ContentFilter{context: ctx}, ctx), do: true
  defp matches_context?(_filter, "all"), do: true
  defp matches_context?(_filter, _requested), do: false

  defp do_check(text, []), do: {:ok, text}

  defp do_check(text, [filter | rest]) do
    case apply_filter(text, filter) do
      {:reject, reason} ->
        {:reject, reason}

      {:flag, reason} ->
        {:flag, reason}

      {:replace, new_text} ->
        do_check(new_text, rest)

      :ok ->
        do_check(text, rest)
    end
  end

  defp apply_filter(text, %ContentFilter{type: "word", pattern: pattern, action: action} = filter) do
    regex = ~r/\b#{Regex.escape(pattern)}\b/i

    if Regex.match?(regex, text) do
      handle_match(text, regex, action, filter)
    else
      :ok
    end
  end

  defp apply_filter(
         text,
         %ContentFilter{type: "phrase", pattern: pattern, action: action} = filter
       ) do
    regex = ~r/#{Regex.escape(pattern)}/i

    if Regex.match?(regex, text) do
      handle_match(text, regex, action, filter)
    else
      :ok
    end
  end

  defp apply_filter(
         text,
         %ContentFilter{type: "regex", pattern: pattern, action: action} = filter
       ) do
    case Regex.compile(pattern, "i") do
      {:ok, regex} ->
        if Regex.match?(regex, text) do
          handle_match(text, regex, action, filter)
        else
          :ok
        end

      {:error, reason} ->
        Logger.warning("Invalid regex pattern in content filter #{filter.id}: #{inspect(reason)}")
        :ok
    end
  end

  defp handle_match(_text, _regex, "reject", filter) do
    {:reject, "Content matched filter: #{filter.pattern}"}
  end

  defp handle_match(_text, _regex, "flag", filter) do
    {:flag, "Content matched filter: #{filter.pattern}"}
  end

  defp handle_match(text, regex, "replace", filter) do
    new_text = Regex.replace(regex, text, filter.replacement || "")
    {:replace, new_text}
  end
end
