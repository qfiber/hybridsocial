defmodule Hybridsocial.Moderation.Filters.NoopEngine do
  @moduledoc """
  No-op content filter engine that always passes content through unchanged.

  Useful for development or when content filtering is intentionally disabled.
  """

  @behaviour Hybridsocial.Moderation.ContentFilterEngine

  require Logger

  @impl true
  def name, do: "none"

  @impl true
  def configurable?, do: false

  @impl true
  def check(text, _context \\ %{}), do: {:ok, text}
end
