defmodule Hybridsocial.Feeds.TimelineAlgorithm do
  @moduledoc """
  Behaviour for timeline algorithms.

  Any module implementing this behaviour can be used as a timeline algorithm
  via the `AlgorithmResolver`. Each implementation must provide:

    * `home_feed/2` - returns a list of timeline entries for the given identity
    * `score_post/2` - scores a single post given a context map
    * `name/0` - returns a human-readable name for the algorithm
  """

  @callback home_feed(identity_id :: String.t(), opts :: keyword()) :: [map()]
  @callback score_post(post :: struct(), context :: map()) :: float()
  @callback name() :: String.t()
end
