defmodule Hybridsocial.Federation.MRF do
  @moduledoc """
  Message Rewrite Facility (MRF) pipeline.

  Runs incoming activities through a configurable chain of policy modules.
  Each policy can accept (optionally transforming), or reject the activity.
  """

  alias Hybridsocial.Config
  alias Hybridsocial.Federation.MRF.{BlockedHashtagPolicy, SimplePolicy}

  @always_on [SimplePolicy, BlockedHashtagPolicy]

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

  @doc """
  Returns the MRF policy modules to run: the always-on ones first, then whatever
  the `mrf_policies` setting adds.

  The always-on policies enforce what admins set in the panel (instance policies
  and hashtag blocks), and those must not silently stop working because of an
  unset or differently-configured setting.
  """
  def configured_policies do
    configured =
      case Config.get("mrf_policies", []) do
        [_ | _] = policies ->
          policies
          |> Enum.map(&resolve_policy_module/1)
          |> Enum.reject(&is_nil/1)

        _ ->
          []
      end

    @always_on ++ (configured -- @always_on)
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
