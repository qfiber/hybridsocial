defmodule Hybridsocial.Federation.MRF.SimplePolicy do
  @moduledoc """
  Accept or reject activities based on the sender's domain.

  Reads from the instance_policies table via the Federation context,
  or falls back to Config-based domain lists.
  """
  @behaviour Hybridsocial.Federation.MRF.Policy

  alias Hybridsocial.Federation.Containment

  @impl true
  def filter(%{"actor" => _} = activity) do
    actor = Containment.get_actor(activity)

    if is_nil(actor) do
      {:reject, "Missing actor"}
    else
      domain = extract_domain(actor)

      cond do
        domain_rejected?(domain) ->
          {:reject, "Domain #{domain} is suspended"}

        domain_silenced?(domain) ->
          # Silenced domains: strip public addressing, allow through
          activity =
            activity
            |> strip_public_addressing()

          {:ok, activity}

        true ->
          {:ok, activity}
      end
    end
  end

  def filter(activity), do: {:ok, activity}

  @impl true
  def describe do
    {:ok, %{name: "simple", description: "Accept/reject by domain policy."}}
  end

  defp domain_rejected?(nil), do: false

  defp domain_rejected?(domain) do
    case Hybridsocial.Repo.get(Hybridsocial.Federation.InstancePolicy, domain) do
      %{policy: policy} when policy in ["suspend", "block"] -> true
      _ -> false
    end
  end

  defp domain_silenced?(nil), do: false

  defp domain_silenced?(domain) do
    case Hybridsocial.Repo.get(Hybridsocial.Federation.InstancePolicy, domain) do
      %{policy: "silence"} -> true
      _ -> false
    end
  end

  defp strip_public_addressing(activity) do
    public = "https://www.w3.org/ns/activitystreams#Public"

    activity
    |> Map.update("to", [], fn to -> List.delete(List.wrap(to), public) end)
    |> Map.update("cc", [], fn cc -> List.delete(List.wrap(cc), public) end)
  end

  defp extract_domain(uri) when is_binary(uri) do
    case URI.parse(uri) do
      %URI{host: host} when is_binary(host) -> String.downcase(host)
      _ -> nil
    end
  end

  defp extract_domain(_), do: nil
end
