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

  # Setting names -> modules. An explicit map instead of building a module name
  # from the string: `String.capitalize("anti_link_spam")` gave
  # "Anti_link_spam", so multi-word policies could never be enabled, and
  # config input never becomes an atom. Names are matched in snake_case, so
  # "noOp" and "no_op" both work.
  @policies %{
    "simple" => Hybridsocial.Federation.MRF.SimplePolicy,
    "blocked_hashtag" => Hybridsocial.Federation.MRF.BlockedHashtagPolicy,
    "keyword" => Hybridsocial.Federation.MRF.KeywordPolicy,
    "hellthread" => Hybridsocial.Federation.MRF.HellthreadPolicy,
    "activity_expiration" => Hybridsocial.Federation.MRF.ActivityExpirationPolicy,
    "anti_link_spam" => Hybridsocial.Federation.MRF.AntiLinkSpamPolicy,
    "no_empty" => Hybridsocial.Federation.MRF.NoEmptyPolicy,
    "drop" => Hybridsocial.Federation.MRF.DropPolicy,
    "no_op" => Hybridsocial.Federation.MRF.NoOpPolicy
  }

  defp resolve_policy_module(name) when is_binary(name),
    do: Map.get(@policies, Macro.underscore(name))

  defp resolve_policy_module(module) when is_atom(module), do: module
  defp resolve_policy_module(_), do: nil
end
