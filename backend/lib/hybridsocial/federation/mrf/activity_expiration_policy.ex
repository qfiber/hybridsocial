defmodule Hybridsocial.Federation.MRF.ActivityExpirationPolicy do
  @moduledoc """
  Adds an `expires_at` field to activities if configured.

  Default expiration: 365 days (configurable via `mrf_activity_expiration_days`).
  Only applies to Create activities.
  """
  @behaviour Hybridsocial.Federation.MRF.Policy

  alias Hybridsocial.Config

  @impl true
  def filter(%{"type" => "Create"} = activity) do
    days = Config.get("mrf_activity_expiration_days", 365)

    if days > 0 do
      expires_at =
        DateTime.utc_now()
        |> DateTime.add(days * 86_400, :second)
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601()

      {:ok, Map.put(activity, "expires_at", expires_at)}
    else
      {:ok, activity}
    end
  end

  def filter(activity), do: {:ok, activity}

  @impl true
  def describe do
    {:ok, %{name: "activity_expiration", description: "Adds expiration timestamps to activities."}}
  end
end
