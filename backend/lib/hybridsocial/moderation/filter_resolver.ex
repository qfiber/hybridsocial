defmodule Hybridsocial.Moderation.FilterResolver do
  @moduledoc """
  Resolves the active content filter engine based on instance configuration.

  The `content_filter_engine` setting controls which engine is used:

    * `"default"` - database-backed filter rules (default)
    * `"custom"` - default engine + webhook-based filtering
    * `"none"` - no-op, all content passes
  """

  alias Hybridsocial.Moderation.Filters.{CustomEngine, DefaultEngine, NoopEngine}

  @spec impl() :: module()
  def impl do
    case Hybridsocial.Config.get("content_filter_engine", "default") do
      "custom" -> CustomEngine
      "none" -> NoopEngine
      _ -> DefaultEngine
    end
  end
end
