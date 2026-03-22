defmodule HybridsocialWeb.Helpers.Pagination do
  @moduledoc """
  Shared pagination helpers for controllers. Ensures limit params are always
  clamped to a safe range to prevent resource exhaustion.
  """

  @default_limit 20
  @max_limit 40

  @doc """
  Clamps a limit value to the range [1, 40].
  Accepts nil, string, or integer input.
  """
  def clamp_limit(nil), do: @default_limit

  def clamp_limit(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> min(max(n, 1), @max_limit)
      :error -> @default_limit
    end
  end

  def clamp_limit(val) when is_integer(val), do: min(max(val, 1), @max_limit)
  def clamp_limit(_), do: @default_limit
end
