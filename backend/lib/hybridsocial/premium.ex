defmodule Hybridsocial.Premium do
  @moduledoc """
  The Premium context. Manages verifications, subscriptions, funding, and donations.
  """
  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Premium.{Verification, VerificationVouch, Subscription, CryptoAddress}

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

  @doc "List verification requests (admin). Filterable by status."
  def list_verifications(opts \\ []) do
    status = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    query =
      Verification
      |> order_by([v], desc: v.inserted_at)
      |> limit(^limit)
      |> offset(^offset)

    query =
      if status do
        where(query, [v], v.status == ^status)
      else
        query
      end

    query
    |> Repo.all()
    |> Repo.preload(:identity)
  end

  @doc "Count pending verification requests."
  def pending_verification_count do
    Verification
    |> where([v], v.status == "pending")
    |> Repo.aggregate(:count)
  end

  # --- Peer Vouching ---

  @vouches_required 3

  @doc "Vouch for a user's verification. Returns {:ok, vouch} or auto-approves if threshold met."
  def vouch_for(verification_id, voucher_id) do
    with verification when not is_nil(verification) <- Repo.get(Verification, verification_id),
         true <- verification.type == "peer_vouch",
         true <- verification.status == "pending",
         false <- verification.identity_id == voucher_id do
      # Check voucher hasn't already vouched
      existing =
        VerificationVouch
        |> where([v], v.verification_id == ^verification_id and v.voucher_id == ^voucher_id)
        |> Repo.one()

      if existing do
        {:error, :already_vouched}
      else
        {:ok, vouch} =
          %VerificationVouch{}
          |> VerificationVouch.changeset(%{verification_id: verification_id, voucher_id: voucher_id})
          |> Repo.insert()

        # Check if threshold is met
        vouch_count =
          VerificationVouch
          |> where([v], v.verification_id == ^verification_id)
          |> Repo.aggregate(:count)

        if vouch_count >= @vouches_required do
          approve_verification(verification_id, nil)
        end

        {:ok, vouch}
      end
    else
      nil -> {:error, :not_found}
      false -> {:error, :cannot_vouch_self}
      true -> {:error, :invalid_verification_type}
    end
  end

  @doc "Get vouches for a verification request."
  def get_vouches(verification_id) do
    VerificationVouch
    |> where([v], v.verification_id == ^verification_id)
    |> Repo.all()
    |> Repo.preload(:voucher)
  end

  @doc "Get the vouch count for a verification."
  def vouch_count(verification_id) do
    VerificationVouch
    |> where([v], v.verification_id == ^verification_id)
    |> Repo.aggregate(:count)
  end

  @doc "Check if a user has already vouched for a verification."
  def has_vouched?(verification_id, voucher_id) do
    VerificationVouch
    |> where([v], v.verification_id == ^verification_id and v.voucher_id == ^voucher_id)
    |> Repo.exists?()
  end

  @doc "Find a pending peer_vouch verification for an identity (for vouch links)."
  def get_peer_verification(identity_id) do
    Verification
    |> where([v], v.identity_id == ^identity_id and v.type == "peer_vouch" and v.status == "pending")
    |> order_by([v], desc: v.inserted_at)
    |> limit(1)
    |> Repo.one()
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

  # --- Crypto Addresses ---

  def list_crypto_addresses(identity_id) do
    CryptoAddress
    |> where([c], c.identity_id == ^identity_id and c.is_public == true)
    |> order_by([c], asc: c.coin)
    |> Repo.all()
  end

  def list_own_crypto_addresses(identity_id) do
    CryptoAddress
    |> where([c], c.identity_id == ^identity_id)
    |> order_by([c], asc: c.coin)
    |> Repo.all()
  end

  def set_crypto_address(identity_id, attrs) do
    %CryptoAddress{}
    |> CryptoAddress.changeset(Map.put(attrs, "identity_id", identity_id))
    |> Repo.insert(
      on_conflict: {:replace, [:address, :label, :is_public, :updated_at]},
      conflict_target: [:identity_id, :coin]
    )
  end

  def remove_crypto_address(identity_id, coin) do
    CryptoAddress
    |> where([c], c.identity_id == ^identity_id and c.coin == ^coin)
    |> Repo.delete_all()
    :ok
  end

  def supported_coins, do: CryptoAddress.supported_coins()
end
