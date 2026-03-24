defmodule Hybridsocial.Moderation.ContentFilterEngine do
  @moduledoc """
  Behaviour for content filtering engines.

  Implementations receive text and a context map, and must return one of:

    * `{:ok, text}` - content is acceptable (possibly transformed)
    * `{:reject, reason}` - content is rejected
    * `{:flag, reason}` - content is flagged for review
  """

  @callback check(text :: String.t(), context :: map()) ::
              {:ok, String.t()} | {:reject, String.t()} | {:flag, String.t()}

  @callback name() :: String.t()

  @callback configurable?() :: boolean()
end
