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
    field :private_key, :string
    field :inbox_url, :string
    field :outbox_url, :string
    field :followers_url, :string
    field :avatar_url, :string
    field :header_url, :string
    field :display_name, :string
    field :bio, :string
    field :metadata, :map, default: %{}
    field :is_locked, :boolean, default: false
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
    field :suspended_at, :utc_datetime_usec
    field :also_known_as, {:array, :string}, default: []
    field :moved_to, :string
    field :trust_level, :integer, default: 0
    field :deleted_at, :utc_datetime_usec
    field :is_suggested, :boolean, default: false
    field :is_name_revoked, :boolean, default: false
    field :force_bot, :boolean, default: false
    field :birthday, :date

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

  @update_fields [
    :display_name,
    :bio,
    :avatar_url,
    :header_url,
    :metadata,
    :is_locked,
    :show_badge,
    :birthday
  ]

  # Subaccounts can also toggle is_bot
  @subaccount_update_fields @update_fields ++ [:is_bot]

  def update_changeset(identity, attrs) do
    fields = if is_subaccount?(identity), do: @subaccount_update_fields, else: @update_fields

    identity
    |> cast(attrs, fields)
    |> validate_length(:display_name, max: 50)
    |> validate_length(:bio, max: 500)
    |> validate_length(:avatar_url, max: 2048)
    |> validate_length(:header_url, max: 2048)
    |> reject_display_name_change_if_verified()
    |> reject_bot_change_if_forced(identity)
    |> reject_type_change_on_main_account(identity)
  end

  def admin_update_changeset(identity, attrs) do
    identity
    |> cast(attrs, @update_fields ++ [:verification_tier, :trust_level, :is_bot, :force_bot, :is_suggested, :is_name_revoked, :is_suspended, :is_silenced, :is_shadow_banned, :force_sensitive, :metadata, :is_admin])
    |> validate_length(:display_name, max: 50)
    |> validate_length(:bio, max: 500)
    |> validate_length(:avatar_url, max: 2048)
    |> validate_length(:header_url, max: 2048)
  end

  defp reject_display_name_change_if_verified(changeset) do
    if get_change(changeset, :display_name) && verified_tier?(changeset.data) do
      add_error(changeset, :display_name, "cannot be changed for verified accounts")
    else
      changeset
    end
  end

  defp verified_tier?(%{verification_tier: tier})
       when tier in ~w(verified_starter verified_creator verified_pro),
       do: true

  defp verified_tier?(_), do: false

  defp reject_bot_change_if_forced(changeset, identity) do
    if identity.force_bot && get_change(changeset, :is_bot) == false do
      delete_change(changeset, :is_bot)
    else
      changeset
    end
  end

  defp reject_type_change_on_main_account(changeset, identity) do
    # Main accounts (no parent) cannot change their type to bot/group/organization
    if not is_subaccount?(identity) do
      case get_change(changeset, :type) do
        nil -> changeset
        "user" -> changeset
        _ -> add_error(changeset, :type, "main accounts must remain as user type")
      end
    else
      changeset
    end
  end

  defp is_subaccount?(%{parent_identity_id: pid}) when is_binary(pid), do: true
  defp is_subaccount?(_), do: false

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
