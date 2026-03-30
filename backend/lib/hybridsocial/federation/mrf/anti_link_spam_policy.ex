defmodule Hybridsocial.Federation.MRF.AntiLinkSpamPolicy do
  @moduledoc """
  Rejects Create activities containing links from accounts with no prior posts.

  This helps prevent spam from newly-created remote accounts that immediately
  post content with links.
  """
  @behaviour Hybridsocial.Federation.MRF.Policy

  alias Hybridsocial.Federation.Containment

  @impl true
  def filter(%{"type" => "Create", "object" => %{"content" => content} = _object} = activity)
      when is_binary(content) do
    if contains_links?(content) do
      actor = Containment.get_actor(activity)

      if actor && new_account?(actor) do
        {:reject, "Anti-link-spam: new account posting links"}
      else
        {:ok, activity}
      end
    else
      {:ok, activity}
    end
  end

  def filter(activity), do: {:ok, activity}

  @impl true
  def describe do
    {:ok, %{name: "anti_link_spam", description: "Rejects posts with links from new accounts."}}
  end

  defp contains_links?(content) do
    Regex.match?(~r/<a\s|https?:\/\/|href=/i, content)
  end

  defp new_account?(actor_uri) do
    import Ecto.Query

    case Hybridsocial.Repo.one(
           from(i in Hybridsocial.Accounts.Identity,
             where: i.ap_actor_url == ^actor_uri,
             select: i.inserted_at
           )
         ) do
      nil ->
        # Unknown actor — treat as new
        true

      inserted_at ->
        # Consider accounts less than 24 hours old as "new"
        DateTime.diff(DateTime.utc_now(), inserted_at, :hour) < 24
    end
  end
end
