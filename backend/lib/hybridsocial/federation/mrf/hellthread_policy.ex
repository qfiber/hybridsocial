defmodule Hybridsocial.Federation.MRF.HellthreadPolicy do
  @moduledoc """
  Rejects posts that mention too many people, preventing hellthread spam.

  Configurable threshold via `mrf_hellthread_threshold` (default: 10).
  """
  @behaviour Hybridsocial.Federation.MRF.Policy

  alias Hybridsocial.Config

  @impl true
  def filter(%{"type" => "Create"} = activity) do
    threshold = Config.get("mrf_hellthread_threshold", 10)

    to = List.wrap(activity["to"])
    cc = List.wrap(activity["cc"])
    recipients = to ++ cc

    # Count recipients that look like actor URIs (not collections)
    mention_count =
      recipients
      |> Enum.reject(&collection_uri?/1)
      |> length()

    if mention_count > threshold do
      {:reject, "Hellthread: #{mention_count} mentions exceeds threshold of #{threshold}"}
    else
      {:ok, activity}
    end
  end

  def filter(activity), do: {:ok, activity}

  @impl true
  def describe do
    {:ok, %{name: "hellthread", description: "Rejects posts mentioning too many people."}}
  end

  defp collection_uri?(uri) when is_binary(uri) do
    uri == "https://www.w3.org/ns/activitystreams#Public" or
      String.ends_with?(uri, "/followers") or
      String.ends_with?(uri, "/following")
  end

  defp collection_uri?(_), do: true
end
