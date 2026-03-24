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

  @doc "Verify domain ownership by checking for a DNS TXT record or rel=me link."
  def verify_domain(identity_id, domain) do
    identity = Hybridsocial.Accounts.get_identity(identity_id)

    if is_nil(identity) do
      {:error, :not_found}
    else
      handle = identity.handle
      expected_proof = "hybridsocial-verify=#{handle}"

      # Check DNS TXT record
      dns_verified = check_dns_txt(domain, expected_proof)

      # Check rel=me link on the domain's homepage
      rel_me_verified = if !dns_verified, do: check_rel_me(domain, identity), else: false

      if dns_verified or rel_me_verified do
        apply_for_verification(identity_id, "domain", %{
          "domain" => domain,
          "method" => if(dns_verified, do: "dns_txt", else: "rel_me"),
          "verified_automatically" => true
        })
        |> case do
          {:ok, verification} ->
            # Auto-approve domain verifications
            approve_verification(verification.id, nil)

          error ->
            error
        end
      else
        {:error, :domain_not_verified}
      end
    end
  end

  defp check_dns_txt(domain, expected_proof) do
    try do
      case :inet_res.lookup(to_charlist(domain), :in, :txt) do
        records when is_list(records) ->
          Enum.any?(records, fn record ->
            txt = record |> List.flatten() |> to_string()
            String.contains?(txt, expected_proof)
          end)

        _ ->
          false
      end
    rescue
      _ -> false
    end
  end

  defp check_rel_me(domain, identity) do
    url = "https://#{domain}"

    try do
      case HTTPoison.get(url, [], recv_timeout: 5_000, timeout: 5_000, follow_redirect: true) do
        {:ok, %{status_code: 200, body: body}} ->
          instance_url = HybridsocialWeb.Endpoint.url()
          profile_url = "#{instance_url}/@#{identity.handle}"

          # Check for <a rel="me" href="https://instance/@handle">
          String.contains?(body, "rel=\"me\"") and String.contains?(body, profile_url)

        _ ->
          false
      end
    rescue
      _ -> false
    end
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
