defmodule Hybridsocial.Accounts.Identity do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_types ~w(user organization)

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

    has_one :user, Hybridsocial.Accounts.User, foreign_key: :identity_id
    has_one :organization, Hybridsocial.Accounts.Organization, foreign_key: :identity_id

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(identity, attrs) do
    identity
    |> cast(attrs, [:type, :handle, :display_name, :bio, :is_locked, :is_bot])
    |> validate_required([:type, :handle])
    |> validate_inclusion(:type, @valid_types)
    |> validate_handle()
    |> validate_length(:display_name, max: 50)
    |> validate_length(:bio, max: 500)
    |> unique_constraint(:handle)
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
    :show_badge
  ]

  def update_changeset(identity, attrs) do
    identity
    |> cast(attrs, @update_fields)
    |> validate_length(:display_name, max: 50)
    |> validate_length(:bio, max: 500)
    |> validate_length(:avatar_url, max: 2048)
    |> validate_length(:header_url, max: 2048)
    |> reject_display_name_change_if_verified()
  end

  def admin_update_changeset(identity, attrs) do
    identity
    |> cast(attrs, @update_fields ++ [:verification_tier, :trust_level])
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
