defmodule Hybridsocial.Admin.BackupTest do
  use Hybridsocial.DataCase

  alias Hybridsocial.Admin.Backup
  alias Hybridsocial.Admin.BackupJob

  defp create_admin(handle, email) do
    {:ok, identity} =
      Hybridsocial.Accounts.register_user(%{
        "handle" => handle,
        "email" => email,
        "password" => "password123",
        "password_confirmation" => "password123"
      })

    identity |> Ecto.Changeset.change(is_admin: true) |> Hybridsocial.Repo.update!()
  end

  describe "create_backup/3" do
    test "creates a backup job record" do
      admin = create_admin("backupadmin", "backupadmin@test.com")

      {:ok, backup_job} = Backup.create_backup(admin.id, "my-secret-passphrase", "full")

      assert backup_job.type == "full"
      assert backup_job.status == "pending"
      assert backup_job.initiated_by == admin.id
      assert backup_job.encryption_key_hash != nil
    end

    test "creates a settings_only backup" do
      admin = create_admin("backupadmin2", "backupadmin2@test.com")

      {:ok, backup_job} = Backup.create_backup(admin.id, "passphrase", "settings_only")

      assert backup_job.type == "settings_only"
    end
  end

  describe "list_backups/0" do
    test "lists all backup jobs" do
      admin = create_admin("listadmin", "listadmin@test.com")

      {:ok, _job1} = Backup.create_backup(admin.id, "pass1", "full")
      {:ok, _job2} = Backup.create_backup(admin.id, "pass2", "settings_only")

      backups = Backup.list_backups()
      assert length(backups) == 2
    end

    test "returns empty list when no backups exist" do
      assert Backup.list_backups() == []
    end
  end

  describe "get_backup/1" do
    test "returns a backup job by id" do
      admin = create_admin("getadmin", "getadmin@test.com")

      {:ok, backup_job} = Backup.create_backup(admin.id, "passphrase", "full")

      found = Backup.get_backup(backup_job.id)
      assert found.id == backup_job.id
      assert found.type == "full"
    end

    test "returns nil for non-existent id" do
      assert Backup.get_backup(Ecto.UUID.generate()) == nil
    end
  end

  describe "derive_key/1" do
    test "derives a 32-byte key from passphrase" do
      key = Backup.derive_key("test-passphrase")
      assert byte_size(key) == 32
    end

    test "same passphrase produces same key" do
      key1 = Backup.derive_key("consistent")
      key2 = Backup.derive_key("consistent")
      assert key1 == key2
    end

    test "different passphrases produce different keys" do
      key1 = Backup.derive_key("passphrase1")
      key2 = Backup.derive_key("passphrase2")
      assert key1 != key2
    end
  end

  describe "hash_passphrase/1" do
    test "produces a hex-encoded hash" do
      hash = Backup.hash_passphrase("test")
      assert is_binary(hash)
      assert String.match?(hash, ~r/^[0-9a-f]+$/)
    end

    test "same passphrase produces same hash" do
      hash1 = Backup.hash_passphrase("test")
      hash2 = Backup.hash_passphrase("test")
      assert hash1 == hash2
    end

    test "different passphrases produce different hashes" do
      hash1 = Backup.hash_passphrase("test1")
      hash2 = Backup.hash_passphrase("test2")
      assert hash1 != hash2
    end
  end

  describe "encryption round-trip" do
    test "data can be encrypted and decrypted with correct passphrase" do
      passphrase = "my-test-passphrase"
      data = "test backup data for encryption round-trip"

      # Compress
      compressed = :zlib.compress(data)

      # Encrypt
      key = Backup.derive_key(passphrase)
      iv = :crypto.strong_rand_bytes(12)

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, compressed, <<>>, 16, true)

      encrypted = iv <> tag <> ciphertext

      # Decrypt
      <<dec_iv::binary-size(12), dec_tag::binary-size(16), dec_ciphertext::binary>> = encrypted

      decrypted =
        :crypto.crypto_one_time_aead(
          :aes_256_gcm,
          key,
          dec_iv,
          dec_ciphertext,
          <<>>,
          dec_tag,
          false
        )

      decompressed = :zlib.uncompress(decrypted)
      assert decompressed == data
    end

    test "decryption fails with wrong passphrase" do
      passphrase = "correct-passphrase"
      wrong_passphrase = "wrong-passphrase"
      data = "secret data"

      compressed = :zlib.compress(data)
      key = Backup.derive_key(passphrase)
      iv = :crypto.strong_rand_bytes(12)

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, compressed, <<>>, 16, true)

      encrypted = iv <> tag <> ciphertext

      # Try to decrypt with wrong key
      wrong_key = Backup.derive_key(wrong_passphrase)
      <<dec_iv::binary-size(12), dec_tag::binary-size(16), dec_ciphertext::binary>> = encrypted

      result =
        :crypto.crypto_one_time_aead(
          :aes_256_gcm,
          wrong_key,
          dec_iv,
          dec_ciphertext,
          <<>>,
          dec_tag,
          false
        )

      assert result == :error
    end
  end

  describe "BackupJob changeset" do
    test "validates type inclusion" do
      changeset = BackupJob.changeset(%BackupJob{}, %{type: "invalid", status: "pending"})
      assert {:type, {"is invalid", _}} = List.first(changeset.errors)
    end

    test "validates status inclusion" do
      changeset = BackupJob.changeset(%BackupJob{}, %{type: "full", status: "invalid"})
      assert {:status, {"is invalid", _}} = List.first(changeset.errors)
    end

    test "accepts valid attributes" do
      changeset = BackupJob.changeset(%BackupJob{}, %{type: "full", status: "pending"})
      assert changeset.valid?
    end
  end
end
