defmodule Hybridsocial.Feeds.AlgorithmResolver do
  @moduledoc """
  Resolves which timeline algorithm implementation to use.

  Supports per-request override via the `:algorithm` option, falling back to
  the instance-wide `default_timeline_algorithm` setting (database-backed).

  ## Supported algorithms

    * `"chronological"` - reverse-chronological feed of followed accounts
    * `"algorithmic"` - ranked feed using interaction affinity and engagement
    * `"trending"` - globally trending posts sorted by engagement score
  """

  @doc """
  Returns the algorithm module to use for the current request.

  ## Options

    * `:algorithm` - explicit algorithm name override (`"chronological"`,
      `"algorithmic"`, or `"trending"`). When `true`, defaults to `"algorithmic"`.
  """
  @spec impl(keyword()) :: module()
  def impl(opts \\ []) do
    case Keyword.get(opts, :algorithm) do
      "algorithmic" -> Hybridsocial.Feeds.Algorithms.Algorithmic
      "trending" -> Hybridsocial.Feeds.Algorithms.Trending
      "chronological" -> Hybridsocial.Feeds.Algorithms.Chronological
      true -> Hybridsocial.Feeds.Algorithms.Algorithmic
      _ -> default_algorithm()
    end
  end

  defp default_algorithm do
    case Hybridsocial.Config.get("default_timeline_algorithm", "chronological") do
      "algorithmic" -> Hybridsocial.Feeds.Algorithms.Algorithmic
      "trending" -> Hybridsocial.Feeds.Algorithms.Trending
      _ -> Hybridsocial.Feeds.Algorithms.Chronological
    end
  end
end
