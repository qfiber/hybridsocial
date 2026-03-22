defmodule Hybridsocial.Premium do
  @moduledoc """
  The Premium context. Manages verifications, subscriptions, funding, and donations.
  """
  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Premium.{Verification, Subscription}

  @premium_features ~w(markdown extended_post_length extra_reactions scheduled_posts post_analytics hd_video)a

  # --- Verification ---

  def apply_for_verification(identity_id, type, metadata \\ %{}) do
    %Verification{}
    |> Verification.changeset(%{
      identity_id: identity_id,
      type: type,
      status: "pending",
      metadata: metadata
    })
    |> Repo.insert()
  end

  def approve_verification(verification_id, _admin_id) do
    case Repo.get(Verification, verification_id) do
      nil ->
        {:error, :not_found}

      verification ->
        verification
        |> Verification.approve_changeset()
        |> Repo.update()
    end
  end

  def reject_verification(verification_id, _admin_id) do
    case Repo.get(Verification, verification_id) do
      nil ->
        {:error, :not_found}

      verification ->
        verification
        |> Verification.reject_changeset()
        |> Repo.update()
    end
  end

  def get_verification(identity_id) do
    Verification
    |> where([v], v.identity_id == ^identity_id)
    |> order_by([v], desc: v.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  def verified?(identity_id) do
    Verification
    |> where([v], v.identity_id == ^identity_id and v.status == "approved")
    |> Repo.exists?()
  end

  # --- Subscription ---

  def get_subscription(identity_id) do
    Subscription
    |> where([s], s.identity_id == ^identity_id and s.status == "active")
    |> order_by([s], desc: s.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  def premium?(identity_id) do
    Subscription
    |> where([s], s.identity_id == ^identity_id and s.plan == "premium" and s.status == "active")
    |> Repo.exists?()
  end

  def create_subscription(identity_id, attrs) do
    %Subscription{}
    |> Subscription.changeset(
      Map.merge(attrs, %{
        identity_id: identity_id,
        started_at: DateTime.utc_now()
      })
    )
    |> Repo.insert()
  end

  def cancel_subscription(identity_id) do
    case get_subscription(identity_id) do
      nil ->
        {:error, :not_found}

      subscription ->
        subscription
        |> Subscription.cancel_changeset()
        |> Repo.update()
    end
  end

  def feature_available?(identity_id, feature) when feature in @premium_features do
    premium?(identity_id)
  end

  def feature_available?(_identity_id, _feature), do: false
end
