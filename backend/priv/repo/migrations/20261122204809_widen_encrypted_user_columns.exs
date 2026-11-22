defmodule Hybridsocial.Repo.Migrations.WidenEncryptedUserColumns do
  use Ecto.Migration

  # These hold Crypto.encrypt/2 output (prefix + base64 of nonce + tag +
  # ciphertext), about 4/3 x (plaintext + 28) bytes, so varchar(255) capped a
  # usable email near 160 chars while validation allows 254 (#325).
  # varchar -> text is a catalog-only change in Postgres: no rewrite.
  def change do
    alter table(:users) do
      modify :email, :text, from: :string
      modify :pending_email, :text, from: :string
      modify :otp_secret, :text, from: :string
    end
  end
end
