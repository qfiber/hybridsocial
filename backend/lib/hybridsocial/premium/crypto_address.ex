defmodule Hybridsocial.Premium.CryptoAddress do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @supported_coins ~w(btc eth xmr sol ltc doge ada dot bnb usdt usdc)

  schema "crypto_addresses" do
    belongs_to :identity, Hybridsocial.Accounts.Identity
    field :coin, :string
    field :address, :string
    field :label, :string
    field :is_public, :boolean, default: true

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(addr, attrs) do
    addr
    |> cast(attrs, [:identity_id, :coin, :address, :label, :is_public])
    |> validate_required([:identity_id, :coin, :address])
    |> validate_inclusion(:coin, @supported_coins)
    |> validate_length(:address, min: 10, max: 256)
    |> validate_length(:label, max: 100)
    |> unique_constraint([:identity_id, :coin])
    |> foreign_key_constraint(:identity_id)
  end

  def supported_coins, do: @supported_coins

  def coin_name(coin) do
    %{
      "btc" => "Bitcoin",
      "eth" => "Ethereum",
      "xmr" => "Monero",
      "sol" => "Solana",
      "ltc" => "Litecoin",
      "doge" => "Dogecoin",
      "ada" => "Cardano",
      "dot" => "Polkadot",
      "bnb" => "BNB",
      "usdt" => "USDT",
      "usdc" => "USDC"
    }[coin] || coin
  end
end
