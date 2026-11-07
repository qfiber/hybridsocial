defmodule Hybridsocial.Premium do
  @moduledoc """
  The Premium context. Manages verifications, subscriptions, funding, and donations.
  """
  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Premium.{Verification, VerificationVouch, Subscription, CryptoAddress}

  @premium_features ~w(markdown extended_post_length extra_reactions scheduled_posts post_analytics hd_video)a

  # --- Verification ---

  @doc """
  Opens a verification request for staff to review. Refused when the account
  is already verified or already has a request waiting.
  """
  def apply_for_verification(identity_id, type, metadata \\ %{}) do
    cond do
      staff_verified?(identity_id) -> {:error, :already_verified}
      pending_verification?(identity_id) -> {:error, :already_pending}
      true -> insert_verification(identity_id, type, metadata)
    end
  end

  defp staff_verified?(identity_id) do
    Identity
    |> where([i], i.id == ^identity_id and not is_nil(i.verified_at))
    |> Repo.exists?()
  end

  defp pending_verification?(identity_id) do
    Verification
    |> where([v], v.identity_id == ^identity_id and v.status == "pending")
    |> Repo.exists?()
  end

  defp insert_verification(identity_id, type, metadata) do
    %Verification{}
    |> Verification.changeset(%{
      identity_id: identity_id,
      type: type,
      status: "pending",
      metadata: metadata
    })
    |> Repo.insert()
  end

  @doc """
  Approves a pending request and verifies the account (#168). Verification is
  separate from the paid `verification_tier`, so it grants the badge and the
  display-name lock but no tier limits.
  """
  def approve_verification(verification_id, admin_id) do
    case Repo.get(Verification, verification_id) do
      nil ->
        {:error, :not_found}

      %Verification{status: "pending"} = verification ->
        Repo.transaction(fn ->
          with {:ok, approved} <-
                 verification |> Verification.approve_changeset() |> Repo.update(),
               {:ok, _identity} <- mark_verified(approved.identity_id, admin_id) do
            approved
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        end)

      _decided ->
        {:error, :not_pending}
    end
  end

  @doc "Verifies an account directly, without a request. Staff only; the caller checks."
  def verify_identity(identity_id, admin_id), do: mark_verified(identity_id, admin_id)

  @doc """
  Removes staff verification. Leaves a paid verified tier alone: that is billing,
  and changes through the tier controls.
  """
  def revoke_verification(identity_id) do
    case Repo.get(Identity, identity_id) do
      nil ->
        {:error, :not_found}

      %Identity{verified_at: nil} ->
        {:error, :not_verified}

      identity ->
        identity |> Ecto.Changeset.change(verified_at: nil, verified_by_id: nil) |> Repo.update()
    end
  end

  defp mark_verified(identity_id, admin_id) do
    case Repo.get(Identity, identity_id) do
      nil ->
        {:error, :not_found}

      identity ->
        identity
        |> Ecto.Changeset.change(
          verified_at: DateTime.utc_now(),
          verified_by_id: admin_id
        )
        |> Repo.update()
    end
  end

  def reject_verification(verification_id, _admin_id, reason \\ nil) do
    case Repo.get(Verification, verification_id) do
      nil ->
        {:error, :not_found}

      %Verification{status: status} when status != "pending" ->
        {:error, :not_pending}

      verification ->
        verification
        |> Verification.reject_changeset(reason)
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

  @doc "Whether staff verified the account. A paid tier is `Identity.verified?/1`'s other half."
  def verified?(identity_id), do: staff_verified?(identity_id)

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

  @doc "Vouch for a user's verification request. Staff review the request; vouches inform them."
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
          |> VerificationVouch.changeset(%{
            verification_id: verification_id,
            voucher_id: voucher_id
          })
          |> Repo.insert()

        # Vouches don't approve on their own: three accounts, possibly one
        # person's, would verify someone with no one reviewing it. Staff see
        # the count and decide.
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
    |> where(
      [v],
      v.identity_id == ^identity_id and v.type == "peer_vouch" and v.status == "pending"
    )
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
