defmodule Hybridsocial.Federation.MRF.NoOpPolicy do
  @moduledoc "Default policy that passes everything through unchanged."
  @behaviour Hybridsocial.Federation.MRF.Policy

  @impl true
  def filter(activity), do: {:ok, activity}

  @impl true
  def describe, do: {:ok, %{name: "no_op", description: "Passes all activities through unchanged."}}
end
