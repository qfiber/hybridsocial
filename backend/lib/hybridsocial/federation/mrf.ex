defmodule Hybridsocial.Federation.MRF do
  @moduledoc """
  Message Rewrite Facility (MRF) pipeline.

  Runs incoming activities through a configurable chain of policy modules.
  Each policy can accept (optionally transforming), or reject the activity.
  """

  alias Hybridsocial.Config

  require Logger

  @doc """
  Runs an activity through all configured MRF policies in order.
  Returns {:ok, activity} if all pass, {:reject, reason} on first rejection.
  """
  def filter_pipeline(activity) do
    policies = configured_policies()

    Enum.reduce_while(policies, {:ok, activity}, fn policy_mod, {:ok, acc} ->
      case policy_mod.filter(acc) do
        {:ok, transformed} ->
          {:cont, {:ok, transformed}}

        {:reject, reason} ->
          Logger.info("MRF policy #{inspect(policy_mod)} rejected activity: #{reason}")
          {:halt, {:reject, reason}}
      end
    end)
  end

  @doc "Returns the list of configured MRF policy modules."
  def configured_policies do
    case Config.get("mrf_policies", []) do
      policies when is_list(policies) and length(policies) > 0 ->
        policies
        |> Enum.map(&resolve_policy_module/1)
        |> Enum.reject(&is_nil/1)

      _ ->
        [Hybridsocial.Federation.MRF.NoOpPolicy]
    end
  end

  @doc "Returns descriptions from all configured policies."
  def describe do
    configured_policies()
    |> Enum.map(fn mod ->
      case mod.describe() do
        {:ok, desc} -> {mod, desc}
        _ -> {mod, %{}}
      end
    end)
    |> Map.new()
  end

  defp resolve_policy_module(name) when is_binary(name) do
    module_name = "Elixir.Hybridsocial.Federation.MRF.#{String.capitalize(name)}Policy"

    try do
      String.to_existing_atom(module_name)
    rescue
      ArgumentError -> nil
    end
  end

  defp resolve_policy_module(module) when is_atom(module), do: module
  defp resolve_policy_module(_), do: nil
end
