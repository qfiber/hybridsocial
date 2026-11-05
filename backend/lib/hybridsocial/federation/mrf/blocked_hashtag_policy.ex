defmodule Hybridsocial.Federation.MRF.BlockedHashtagPolicy do
  @moduledoc """
  Rejects remote posts carrying a hashtag blocked with the `reject` action.

  Tags come from the same two sources ingestion links them from: the AP `tag`
  array, and the body for peers that only inline them.
  """
  @behaviour Hybridsocial.Federation.MRF.Policy

  alias Hybridsocial.Federation.ActivityMapper
  alias Hybridsocial.Moderation
  alias Hybridsocial.Social.Posts

  @impl true
  def filter(%{"type" => type, "object" => %{} = object} = activity)
      when type in ["Create", "Update"] do
    names =
      (ActivityMapper.extract_hashtags(object["tag"]) ++ Posts.extract_hashtags(object["content"]))
      |> Enum.map(fn {name, _display} -> name end)

    case Moderation.rejected_hashtag_among(names) do
      nil -> {:ok, activity}
      name -> {:reject, "Hashtag ##{name} is blocked"}
    end
  end

  def filter(activity), do: {:ok, activity}

  @impl true
  def describe do
    {:ok, %{name: "blocked_hashtag", description: "Reject posts carrying blocked hashtags."}}
  end
end
