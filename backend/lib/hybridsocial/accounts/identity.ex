defmodule Hybridsocial.Accounts.Identity do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_types ~w(user organization bot group)

  schema "identities" do
    field :type, :string
    field :handle, :string
    field :ap_actor_url, :string
    field :public_key, :string
    # Encrypted at rest — a leaked DB dump must not hand over the keys that
    # let someone forge this actor's federation signatures.
    field :private_key, Hybridsocial.Crypto.EncryptedBinary, context: "identity.private_key"
    field :inbox_url, :string
    field :outbox_url, :string
    field :followers_url, :string
    field :following_url, :string
    field :featured_url, :string
    field :shared_inbox_url, :string
    # Whether this identity is hosted on our instance (we hold its private
    # key and sign as it). Native users get `/actors/<uuid>`; actors
    # imported from a migrated instance keep their original `ap_actor_url`
    # but are still local. Remote (federated) identity rows are false.
    field :is_local, :boolean, default: true
    field :avatar_url, :string
    field :header_url, :string
    field :display_name, :string
    field :bio, :string
    # Custom emoji manifest mirrored from a remote actor's AP `tag`, used to
    # render `:shortcode:` in the display_name/bio. Empty for local users.
    field :emojis, {:array, :map}, default: []
    # Remote actor's human HTML profile URL (AP `url`), for "view on original".
    field :profile_url, :string
    field :metadata, :map, default: %{}
    # Staff-set posting limits; see Social.PostRateLimit. Deliberately in no
    # changeset's cast list: it is only written by the admin endpoint.
    field :post_limits, :map, default: %{}
    field :is_locked, :boolean, default: false
    # Who can invite this identity into a group or organization
    # (page). Values: "anyone" (default), "only_follows" (only users
    # this identity follows can invite them), "nobody" (all invites
    # rejected at the DB level before any notification fires).
    field :allow_group_invites, :string, default: "anyone"
    field :allow_page_invites, :string, default: "anyone"
    field :is_bot, :boolean, default: false
    field :is_admin, :boolean, default: false
    field :is_suspended, :boolean, default: false
    field :is_silenced, :boolean, default: false
    field :silenced_until, :utc_datetime_usec
    field :silence_reason, :string
    field :is_shadow_banned, :boolean, default: false
    field :force_sensitive, :boolean, default: false
    field :show_badge, :boolean, default: true
    field :verification_tier, :string, default: "free"
    # Set when staff verify the account (#168), separately from the paid
    # `verification_tier`. Never cast from params: `Premium` sets it.
    field :verified_at, :utc_datetime_usec
    field :verified_by_id, :binary_id
    field :suspended_at, :utc_datetime_usec
    field :also_known_as, {:array, :string}, default: []
    field :moved_to, :string
    field :trust_level, :integer, default: 0
    field :deleted_at, :utc_datetime_usec
    field :is_suggested, :boolean, default: false
    field :is_name_revoked, :boolean, default: false
    field :force_bot, :boolean, default: false
    field :birthday, :date
    field :location, :string
    field :onboarded_at, :utc_datetime_usec

    # Whether this identity appears in public directory listings (new-users
    # widget, /directory page, AP actor discoverable flag). Default true —
    # opt-out, not opt-in. Users who want privacy can toggle it off in
    # settings.
    field :discoverable, :boolean, default: true

    # Staff-set: keep search engines off this profile and its posts, even though
    # the page stays viewable. Deliberately in no changeset's cast list, it is
    # only written by the admin endpoint. See Accounts.PublicProfile.
    field :search_indexing_blocked, :boolean, default: false

    # Whether social crawlers (FacebookExternalHit, TelegramBot, etc.)
    # see full profile info when unfurling a /@handle link on external
    # platforms. When false, crawlers get a placeholder OG shell only.
    # Default true — opt-out.
    field :allow_unfurl, :boolean, default: true

    # When true, the profile serializer returns nil for
    # followers_count / following_count to viewers other than the
    # owner. Counts are still computed for own-profile views and for
    # admin moderation surfaces.
    field :hide_follow_counts, :boolean, default: false

    # Automatic post deletion (#254): delete this identity's posts once they
    # are this many months old (1..12). nil = off, the default.
    # `auto_delete_enabled_at` is set when it is switched on and never cast
    # from params; posts published before it are kept. See
    # Social.AutoDeleteWorker.
    field :auto_delete_after_months, :integer
    field :auto_delete_enabled_at, :utc_datetime_usec

    # Optional account recovery code. Hashed. See Accounts.RecoveryCode
    # and Accounts.generate_recovery_code/2 / recover_account/4.
    field :recovery_code_hash, :string
    field :recovery_code_generated_at, :utc_datetime_usec
    field :recovery_code_last_used_at, :utc_datetime_usec
    field :recovered_at, :utc_datetime_usec

    # Subaccount hierarchy: bots, groups, and organizations belong to a parent user
    belongs_to :parent, __MODULE__, foreign_key: :parent_identity_id
    has_many :children, __MODULE__, foreign_key: :parent_identity_id

    has_one :user, Hybridsocial.Accounts.User, foreign_key: :identity_id
    has_one :organization, Hybridsocial.Accounts.Organization, foreign_key: :identity_id
    has_one :bot, Hybridsocial.Accounts.Bot, foreign_key: :identity_id
    has_one :group, Hybridsocial.Groups.Group, foreign_key: :identity_id

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(identity, attrs) do
    identity
    |> cast(attrs, [:type, :handle, :display_name, :bio, :is_locked, :is_bot, :parent_identity_id])
    |> validate_required([:type, :handle])
    |> validate_inclusion(:type, @valid_types)
    |> validate_subaccount_type()
    |> reject_bot_on_main_account()
    |> validate_handle()
    |> validate_length(:display_name, max: 50)
    |> validate_length(:bio, max: 500)
    |> unique_constraint(:handle)
    |> foreign_key_constraint(:parent_identity_id)
    |> generate_ap_urls()
    |> generate_keys()
  end

  @import_fields [
    :id,
    :type,
    :handle,
    :display_name,
    :bio,
    :avatar_url,
    :header_url,
    :ap_actor_url,
    :public_key,
    :private_key,
    :inbox_url,
    :outbox_url,
    :followers_url,
    :following_url,
    :featured_url,
    :shared_inbox_url,
    :is_locked,
    :is_bot,
    :discoverable,
    :also_known_as,
    :metadata,
    :onboarded_at
  ]

  @doc """
  Insert a legacy local identity migrated from another instance,
  preserving its original ActivityPub URI and RSA keypair instead of
  generating fresh ones. The row is marked local so we serve its actor
  document and sign outgoing requests as it — which is what keeps remote
  servers accepting us after the platform swap.

  Unlike `create_changeset/2` this does NOT call `generate_ap_urls/1` or
  `generate_keys/1`; the caller must supply `ap_actor_url`, `public_key`
  and `private_key` (the exact PEM the source instance served).
  """
  def import_changeset(identity \\ %__MODULE__{}, attrs) do
    identity
    |> cast(attrs, @import_fields)
    |> put_change(:is_local, true)
    |> validate_required([:type, :handle, :ap_actor_url, :public_key, :private_key])
    |> validate_inclusion(:type, @valid_types)
    # Imported handles may contain hyphens (Pleroma/Rebased allow them);
    # native registration stays stricter. WebFinger must answer the exact
    # original handle so remote discovery keeps working after the swap.
    |> validate_format(:handle, ~r/^[a-zA-Z0-9_-]+$/)
    |> unique_constraint(:handle)
    |> unique_constraint(:ap_actor_url)
  end

  @update_fields [
    :display_name,
    :bio,
    :avatar_url,
    :header_url,
    :is_locked,
    :allow_group_invites,
    :allow_page_invites,
    :show_badge,
    :birthday,
    :location,
    :discoverable,
    :allow_unfurl,
    :auto_delete_after_months,
    :hide_follow_counts
  ]

  # Subaccounts can also toggle is_bot
  @subaccount_update_fields @update_fields ++ [:is_bot]

  def update_changeset(identity, attrs) do
    fields = if subaccount?(identity), do: @subaccount_update_fields, else: @update_fields

    identity
    |> cast(attrs, fields)
    |> validate_length(:display_name, max: 50)
    |> validate_length(:bio, max: 500)
    |> validate_length(:location, max: 100)
    |> validate_length(:avatar_url, max: 2048)
    |> validate_length(:header_url, max: 2048)
    |> validate_inclusion(:allow_group_invites, ~w(anyone only_follows nobody))
    |> validate_inclusion(:allow_page_invites, ~w(anyone only_follows nobody))
    |> validate_number(:auto_delete_after_months,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 12
    )
    |> track_auto_delete_enabled()
    |> reject_display_name_change_if_verified()
    |> reject_bot_change_if_forced(identity)
    |> reject_type_change_on_main_account(identity)
  end

  # Stamp when auto-delete is switched on, clear it when switched off.
  # Changing the period while it is on keeps the original stamp, so posts
  # from before it was first enabled stay safe.
  defp track_auto_delete_enabled(changeset) do
    case fetch_change(changeset, :auto_delete_after_months) do
      {:ok, nil} ->
        put_change(changeset, :auto_delete_enabled_at, nil)

      {:ok, _months} ->
        if is_nil(get_field(changeset, :auto_delete_enabled_at)) do
          put_change(changeset, :auto_delete_enabled_at, DateTime.utc_now())
        else
          changeset
        end

      :error ->
        changeset
    end
  end

  @profile_field_name_max 60
  @profile_field_value_max 280

  @doc """
  The profile fields a user wrote, under `metadata["profile_fields"]`. This is the
  only part of `metadata` a user can change, and only through this function. The
  caller applies the tier's cap on how many.
  """
  def put_profile_fields(changeset, fields) when is_list(fields) do
    metadata = get_field(changeset, :metadata) || %{}

    put_change(
      changeset,
      :metadata,
      Map.put(metadata, "profile_fields", clean_profile_fields(fields))
    )
  end

  @doc """
  An identity's profile fields as `[%{"name" => _, "value" => _}]`, safe to show or
  federate. Rows written before writes were restricted can hold anything here, so
  this cleans on the way out too.
  """
  def profile_fields(%{metadata: %{"profile_fields" => fields}}) when is_list(fields) do
    clean_profile_fields(fields)
  end

  def profile_fields(_identity), do: []

  defp clean_profile_fields(fields) do
    fields
    |> Enum.flat_map(fn
      %{"name" => name, "value" => value} when is_binary(name) and is_binary(value) ->
        [
          %{
            "name" => clamp(name, @profile_field_name_max),
            "value" => clamp(value, @profile_field_value_max)
          }
        ]

      _ ->
        []
    end)
    |> Enum.reject(&(&1["name"] == "" and &1["value"] == ""))
  end

  defp clamp(value, max), do: value |> String.trim() |> String.slice(0, max)

  def admin_update_changeset(identity, attrs) do
    identity
    |> cast(
      attrs,
      @update_fields ++
        [
          :verification_tier,
          :trust_level,
          :is_bot,
          :force_bot,
          :is_suggested,
          :is_name_revoked,
          :is_suspended,
          :is_silenced,
          :is_shadow_banned,
          :force_sensitive,
          :metadata,
          :is_admin
        ]
    )
    |> validate_length(:display_name, max: 50)
    |> validate_length(:bio, max: 500)
    |> validate_length(:avatar_url, max: 2048)
    |> validate_length(:header_url, max: 2048)
  end

  defp reject_display_name_change_if_verified(changeset) do
    if get_change(changeset, :display_name) && verified?(changeset.data) do
      add_error(
        changeset,
        :display_name,
        "Verified accounts can't change their display name. Contact an admin."
      )
    else
      changeset
    end
  end

  @verified_tiers ~w(verified_starter verified_creator verified_pro)

  @doc """
  Whether the account shows as verified: staff verified it, or it holds a paid
  verified tier.
  """
  def verified?(%{verified_at: %DateTime{}}), do: true
  def verified?(%{verification_tier: tier}) when tier in @verified_tiers, do: true
  def verified?(_), do: false

  defp reject_bot_change_if_forced(changeset, identity) do
    if identity.force_bot && get_change(changeset, :is_bot) == false do
      delete_change(changeset, :is_bot)
    else
      changeset
    end
  end

  defp reject_type_change_on_main_account(changeset, identity) do
    # Main accounts (no parent) cannot change their type to bot/group/organization
    if subaccount?(identity) do
      changeset
    else
      case get_change(changeset, :type) do
        nil -> changeset
        "user" -> changeset
        _ -> add_error(changeset, :type, "main accounts must remain as user type")
      end
    end
  end

  defp subaccount?(%{parent_identity_id: pid}) when is_binary(pid), do: true
  defp subaccount?(_), do: false

  defp reject_bot_on_main_account(changeset) do
    parent_id = get_field(changeset, :parent_identity_id)
    is_bot = get_field(changeset, :is_bot)

    if is_nil(parent_id) && is_bot == true do
      add_error(changeset, :is_bot, "main accounts cannot be marked as bot")
    else
      changeset
    end
  end

  def suspend_changeset(identity) do
    identity
    |> change(is_suspended: true, suspended_at: DateTime.utc_now())
  end

  def unsuspend_changeset(identity) do
    identity
    |> change(is_suspended: false, suspended_at: nil)
  end

  def silence_changeset(identity, attrs) do
    identity
    |> cast(attrs, [:is_silenced, :silenced_until, :silence_reason])
    |> put_change(:is_silenced, true)
  end

  def unsilence_changeset(identity) do
    identity
    |> change(is_silenced: false, silenced_until: nil, silence_reason: nil)
  end

  def shadow_ban_changeset(identity) do
    identity
    |> change(is_shadow_banned: true)
  end

  def unshadow_ban_changeset(identity) do
    identity
    |> change(is_shadow_banned: false)
  end

  def force_sensitive_changeset(identity) do
    identity
    |> change(force_sensitive: true)
  end

  def unforce_sensitive_changeset(identity) do
    identity
    |> change(force_sensitive: false)
  end

  @doc "Returns true if the identity is currently silenced (checking expiry)."
  def silenced?(%__MODULE__{is_silenced: false}), do: false

  def silenced?(%__MODULE__{is_silenced: true, silenced_until: nil}), do: true

  def silenced?(%__MODULE__{is_silenced: true, silenced_until: until}) do
    DateTime.compare(DateTime.utc_now(), until) == :lt
  end

  def soft_delete_changeset(identity) do
    identity
    |> change(deleted_at: DateTime.utc_now())
  end

  @doc "Reverse a soft delete by clearing `deleted_at`."
  def restore_changeset(identity) do
    identity
    |> change(deleted_at: nil)
  end

  @doc "Returns true if this identity type must have a parent (is a subaccount)."
  def subaccount_type?(type) when type in ~w(bot group organization), do: true
  def subaccount_type?(_), do: false

  defp validate_subaccount_type(changeset) do
    type = get_field(changeset, :type)
    parent_id = get_field(changeset, :parent_identity_id)

    cond do
      subaccount_type?(type) && is_nil(parent_id) ->
        add_error(changeset, :parent_identity_id, "is required for #{type} accounts")

      type == "user" && !is_nil(parent_id) ->
        add_error(changeset, :parent_identity_id, "user accounts cannot have a parent")

      true ->
        changeset
    end
  end

  defp validate_handle(changeset) do
    changeset
    |> validate_length(:handle, min: 1, max: 20)
    |> validate_format(:handle, ~r/^[a-zA-Z0-9_]+$/,
      message: "only letters, numbers, and underscores allowed"
    )
  end

  defp generate_ap_urls(changeset) do
    case get_change(changeset, :handle) do
      nil ->
        changeset

      _handle ->
        id = get_field(changeset, :id) || Ecto.UUID.generate()

        changeset
        |> put_change(:id, id)
        |> put_change(:ap_actor_url, "#{base_url()}/actors/#{id}")
        |> put_change(:inbox_url, "#{base_url()}/actors/#{id}/inbox")
        |> put_change(:outbox_url, "#{base_url()}/actors/#{id}/outbox")
        |> put_change(:followers_url, "#{base_url()}/actors/#{id}/followers")
    end
  end

  defp generate_keys(changeset) do
    if get_change(changeset, :handle) do
      {public_key, private_key} = generate_rsa_keypair()

      changeset
      |> put_change(:public_key, public_key)
      |> put_change(:private_key, private_key)
    else
      changeset
    end
  end

  defp generate_rsa_keypair do
    private_key = :public_key.generate_key({:rsa, 2048, 65537})
    private_entry = :public_key.pem_entry_encode(:RSAPrivateKey, private_key)
    private_pem = :public_key.pem_encode([private_entry])

    rsa_public = {:RSAPublicKey, elem(private_key, 2), elem(private_key, 3)}
    public_entry = :public_key.pem_entry_encode(:SubjectPublicKeyInfo, rsa_public)
    public_pem = :public_key.pem_encode([public_entry])

    {public_pem, private_pem}
  end

  defp base_url do
    HybridsocialWeb.Endpoint.url()
  end
end
