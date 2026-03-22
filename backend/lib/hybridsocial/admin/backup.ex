defmodule Hybridsocial.Admin.Backup do
  @moduledoc """
  Context module for managing database backups.
  Handles creation, encryption, listing, and restoration of backups.
  """

  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Admin.BackupJob

  require Logger

  @backup_dir "priv/backups"
  @iterations 100_000
  @key_length 32
  @iv_length 12
  @tag_length 16

  # --- Public API ---

  @doc """
  Creates a backup job record and spawns an async task to generate the backup.
  """
  def create_backup(admin_id, passphrase, type \\ "full") do
    key_hash = hash_passphrase(passphrase)

    attrs = %{
      type: type,
      status: "pending",
      encryption_key_hash: key_hash,
      initiated_by: admin_id
    }

    case %BackupJob{} |> BackupJob.changeset(attrs) |> Repo.insert() do
      {:ok, backup_job} ->
        caller = self()

        Task.start(fn ->
          try do
            Ecto.Adapters.SQL.Sandbox.allow(Hybridsocial.Repo, caller, self())
          rescue
            _ -> :ok
          end

          generate_backup(backup_job.id, passphrase)
        end)

        {:ok, backup_job}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Generates the actual backup file: pg_dump -> compress -> encrypt -> store.
  """
  def generate_backup(backup_id, passphrase) do
    backup_job =
      case Repo.get(BackupJob, backup_id) do
        nil -> raise "Backup job #{backup_id} not found"
        job -> job
      end

    # Update status to running
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    {:ok, backup_job} =
      backup_job
      |> BackupJob.changeset(%{status: "running", started_at: now})
      |> Repo.update(stale_error_field: :id)

    try do
      # Get DB connection info from Repo config
      config = Repo.config()
      db_name = Keyword.fetch!(config, :database)
      hostname = Keyword.get(config, :hostname, "localhost")
      port = Keyword.get(config, :port, 5432)
      username = Keyword.get(config, :username, "postgres")
      password = Keyword.get(config, :password, "")

      # Set PGPASSWORD environment variable
      env = [{"PGPASSWORD", to_string(password)}]

      args = [
        "-h",
        to_string(hostname),
        "-p",
        to_string(port),
        "-U",
        to_string(username),
        "-Fc",
        db_name
      ]

      # Run pg_dump
      case System.cmd("pg_dump", args, env: env, stderr_to_stdout: true) do
        {dump_data, 0} ->
          # Compress with zlib
          compressed = :zlib.compress(dump_data)

          # Encrypt with AES-256-GCM
          key = derive_key(passphrase)
          iv = :crypto.strong_rand_bytes(@iv_length)

          {ciphertext, tag} =
            :crypto.crypto_one_time_aead(
              :aes_256_gcm,
              key,
              iv,
              compressed,
              <<>>,
              @tag_length,
              true
            )

          # Build encrypted payload: iv <> tag <> ciphertext
          encrypted = iv <> tag <> ciphertext

          # Write to file
          ensure_backup_dir()
          filename = "backup_#{backup_id}_#{DateTime.to_unix(DateTime.utc_now())}.enc"
          file_path = Path.join(backup_dir(), filename)
          File.write!(file_path, encrypted)

          file_size = byte_size(encrypted)

          # Update record
          backup_job
          |> BackupJob.changeset(%{
            status: "completed",
            file_path: file_path,
            file_size: file_size,
            completed_at: DateTime.utc_now()
          })
          |> Repo.update()

        {error_output, _exit_code} ->
          Logger.error("pg_dump failed: #{error_output}")

          backup_job
          |> BackupJob.changeset(%{status: "failed", completed_at: DateTime.utc_now()})
          |> Repo.update()
      end
    rescue
      e ->
        Logger.error("Backup generation failed: #{inspect(e)}")

        backup_job
        |> BackupJob.changeset(%{status: "failed", completed_at: DateTime.utc_now()})
        |> Repo.update()
    end
  end

  @doc """
  Lists all backup jobs, ordered by most recent first.
  """
  def list_backups do
    BackupJob
    |> order_by([b], desc: b.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single backup job by ID.
  """
  def get_backup(id) do
    Repo.get(BackupJob, id)
  end

  @doc """
  Decrypts and verifies a backup file. Does NOT actually restore the database.
  This is a stub that validates the passphrase can decrypt the backup.
  """
  def restore_backup(backup_id, passphrase) do
    case get_backup(backup_id) do
      nil ->
        {:error, :not_found}

      %BackupJob{file_path: nil} ->
        {:error, :no_file}

      %BackupJob{file_path: file_path, encryption_key_hash: stored_hash} ->
        # Verify passphrase matches
        if hash_passphrase(passphrase) != stored_hash do
          {:error, :invalid_passphrase}
        else
          case File.read(file_path) do
            {:ok, encrypted} ->
              case decrypt_backup(encrypted, passphrase) do
                {:ok, _decompressed} ->
                  {:ok, :verified}

                {:error, reason} ->
                  {:error, reason}
              end

            {:error, reason} ->
              {:error, {:file_read_error, reason}}
          end
        end
    end
  end

  # --- Key derivation and hashing ---

  @doc """
  Derives an AES-256 key from a passphrase using iterative SHA-256 hashing.
  PBKDF2-like key derivation using :crypto.hash iteratively.
  """
  def derive_key(passphrase) do
    salt = "hybridsocial_backup_salt"
    initial = :crypto.hash(:sha256, passphrase <> salt)

    Enum.reduce(1..@iterations, initial, fn _i, acc ->
      :crypto.hash(:sha256, acc <> passphrase)
    end)
    |> binary_part(0, @key_length)
  end

  @doc """
  Hashes a passphrase for storage/verification purposes (SHA256).
  """
  def hash_passphrase(passphrase) do
    :crypto.hash(:sha256, passphrase)
    |> Base.encode16(case: :lower)
  end

  # --- Private helpers ---

  defp decrypt_backup(encrypted, passphrase) do
    key = derive_key(passphrase)

    # Extract iv, tag, and ciphertext
    <<iv::binary-size(@iv_length), tag::binary-size(@tag_length), ciphertext::binary>> = encrypted

    case :crypto.crypto_one_time_aead(
           :aes_256_gcm,
           key,
           iv,
           ciphertext,
           <<>>,
           tag,
           false
         ) do
      :error ->
        {:error, :decryption_failed}

      decrypted ->
        # Decompress
        decompressed = :zlib.uncompress(decrypted)
        {:ok, decompressed}
    end
  end

  defp ensure_backup_dir do
    dir = backup_dir()
    File.mkdir_p!(dir)
  end

  defp backup_dir do
    Application.app_dir(:hybridsocial, @backup_dir)
  rescue
    _ -> Path.join(File.cwd!(), @backup_dir)
  end
end
