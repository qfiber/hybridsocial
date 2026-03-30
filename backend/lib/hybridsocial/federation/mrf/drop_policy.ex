defmodule Hybridsocial.Federation.MRF.DropPolicy do
  @moduledoc "Drops all activities. Useful for testing or quarantine scenarios."
  @behaviour Hybridsocial.Federation.MRF.Policy

  @impl true
  def filter(_activity), do: {:reject, "Drop policy active — all activities rejected"}

  @impl true
  def describe, do: {:ok, %{name: "drop", description: "Rejects all activities."}}
end
