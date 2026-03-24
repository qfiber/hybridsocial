defmodule Hybridsocial.Moderation.IpBan do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ip_bans" do
    field :ip_address, :string
    field :subnet_mask, :string
    field :reason, :string
    field :expires_at, :utc_datetime_usec

    belongs_to :creator, Hybridsocial.Accounts.Identity, foreign_key: :created_by

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(ip_ban, attrs) do
    ip_ban
    |> cast(attrs, [:ip_address, :subnet_mask, :reason, :expires_at, :created_by])
    |> validate_required([:ip_address])
    |> validate_ip_address()
    |> validate_subnet_mask()
  end

  defp validate_ip_address(changeset) do
    validate_change(changeset, :ip_address, fn :ip_address, ip ->
      case :inet.parse_address(to_charlist(ip)) do
        {:ok, _} -> []
        {:error, _} -> [ip_address: "is not a valid IP address"]
      end
    end)
  end

  defp validate_subnet_mask(changeset) do
    case get_change(changeset, :subnet_mask) do
      nil ->
        changeset

      _ ->
        validate_change(changeset, :subnet_mask, fn :subnet_mask, mask ->
          case Integer.parse(mask) do
            {bits, ""} when bits >= 0 and bits <= 128 -> []
            _ -> [subnet_mask: "must be a valid CIDR prefix length (0-128)"]
          end
        end)
    end
  end
end
