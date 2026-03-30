defmodule Hybridsocial.Federation.MRF.Policy do
  @moduledoc """
  Behaviour for MRF policy modules.

  Each policy must implement `filter/1` and `describe/0`.
  """

  @callback filter(map()) :: {:ok, map()} | {:reject, String.t()}
  @callback describe() :: {:ok, map()}
end
