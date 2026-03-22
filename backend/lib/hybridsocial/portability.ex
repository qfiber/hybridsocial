defmodule Hybridsocial.Portability do
  @moduledoc """
  The Portability context. Manages data exports, imports, and account deletion.
  """
  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Portability.{DataExport, AccountDeletion}
  alias Hybridsocial.Accounts

  @deletion_delay_days 30

  # --- Data Export ---

  def request_export(identity_id) do
    %DataExport{}
    |> DataExport.changeset(%{
      identity_id: identity_id,
      status: "pending",
      requested_at: DateTime.utc_now()
    })
    |> Repo.insert()
  end

  def get_exports(identity_id) do
    DataExport
    |> where([e], e.identity_id == ^identity_id)
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
  end

  def get_export(id, identity_id) do
    DataExport
    |> where([e], e.id == ^id and e.identity_id == ^identity_id)
    |> Repo.one()
  end

  def generate_export(export_id) do
    case Repo.get(DataExport, export_id) do
      nil ->
        {:error, :not_found}

      export ->
        export
        |> Ecto.Changeset.change(status: "processing")
        |> Repo.update!()

        try do
          identity_id = export.identity_id
          identity = Accounts.get_identity(identity_id)

          data = %{
            profile: serialize_profile(identity),
            posts: collect_posts(identity_id),
            follows: collect_follows(identity_id),
            followers: collect_followers(identity_id),
            blocks: collect_blocks(identity_id),
            mutes: collect_mutes(identity_id),
            bookmarks: collect_bookmarks(identity_id),
            lists: collect_lists(identity_id)
          }

          export_dir = export_directory()
          File.mkdir_p!(export_dir)

          json_path = Path.join(export_dir, "#{export.id}.json")
          File.write!(json_path, Jason.encode!(data, pretty: true))

          tar_path = Path.join(export_dir, "#{export.id}.tar.gz")

          :erl_tar.create(
            String.to_charlist(tar_path),
            [{String.to_charlist("export.json"), File.read!(json_path)}],
            [:compressed]
          )

          file_size = File.stat!(tar_path).size
          File.rm!(json_path)

          export
          |> DataExport.complete_changeset(tar_path, file_size)
          |> Repo.update()
        rescue
          e ->
            export
            |> DataExport.fail_changeset()
            |> Repo.update()

            {:error, Exception.message(e)}
        end
    end
  end

  # --- Data Import ---

  def import_follows(identity_id, csv_data) do
    csv_data
    |> String.split("\n", trim: true)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.reduce({0, 0}, fn line, {success, failed} ->
      handle = String.trim(line)

      case Accounts.get_identity_by_handle(handle) do
        nil ->
          {success, failed + 1}

        target ->
          case Hybridsocial.Social.follow(identity_id, target.id) do
            {:ok, _} -> {success + 1, failed}
            _ -> {success, failed + 1}
          end
      end
    end)
    |> then(fn {success, failed} -> {:ok, %{imported: success, failed: failed}} end)
  end

  def import_blocks(identity_id, csv_data) do
    csv_data
    |> String.split("\n", trim: true)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.reduce({0, 0}, fn line, {success, failed} ->
      handle = String.trim(line)

      case Accounts.get_identity_by_handle(handle) do
        nil ->
          {success, failed + 1}

        target ->
          case Hybridsocial.Social.block(identity_id, target.id) do
            {:ok, _} -> {success + 1, failed}
            _ -> {success, failed + 1}
          end
      end
    end)
    |> then(fn {success, failed} -> {:ok, %{imported: success, failed: failed}} end)
  end

  # --- Account Deletion ---

  def request_deletion(identity_id, reason \\ nil) do
    scheduled_for = DateTime.add(DateTime.utc_now(), @deletion_delay_days * 24 * 3600, :second)

    %AccountDeletion{}
    |> AccountDeletion.changeset(%{
      identity_id: identity_id,
      reason: reason,
      scheduled_for: scheduled_for
    })
    |> Repo.insert()
  end

  def cancel_deletion(identity_id) do
    case get_active_deletion(identity_id) do
      nil ->
        {:error, :not_found}

      deletion ->
        deletion
        |> AccountDeletion.cancel_changeset()
        |> Repo.update()
    end
  end

  def get_deletion(identity_id) do
    get_active_deletion(identity_id)
  end

  def execute_deletion(deletion_id) do
    case Repo.get(AccountDeletion, deletion_id) do
      nil ->
        {:error, :not_found}

      deletion ->
        identity = Accounts.get_identity(deletion.identity_id)

        if identity do
          # Soft delete identity
          Accounts.soft_delete_identity(identity)

          # TODO: Send AP Delete activity
          # Hybridsocial.Federation.publish_delete(identity)

          # Anonymize data
          anonymize_identity(identity)
        end

        # Mark deletion as executed
        deletion
        |> AccountDeletion.execute_changeset()
        |> Repo.update()
    end
  end

  # --- Private helpers ---

  defp get_active_deletion(identity_id) do
    AccountDeletion
    |> where(
      [d],
      d.identity_id == ^identity_id and is_nil(d.cancelled_at) and is_nil(d.executed_at)
    )
    |> order_by([d], desc: d.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  defp anonymize_identity(identity) do
    identity
    |> Ecto.Changeset.change(%{
      display_name: nil,
      bio: nil,
      avatar_url: nil,
      header_url: nil,
      metadata: %{}
    })
    |> Repo.update()
  end

  defp export_directory do
    Path.join([Application.get_env(:hybridsocial, :upload_dir, "priv/uploads"), "exports"])
  end

  defp serialize_profile(nil), do: %{}

  defp serialize_profile(identity) do
    %{
      id: identity.id,
      handle: identity.handle,
      display_name: identity.display_name,
      bio: identity.bio,
      avatar_url: identity.avatar_url,
      header_url: identity.header_url
    }
  end

  defp collect_posts(identity_id) do
    Hybridsocial.Social.Post
    |> where([p], p.identity_id == ^identity_id and is_nil(p.deleted_at))
    |> select([p], %{id: p.id, content: p.content, inserted_at: p.inserted_at})
    |> Repo.all()
  end

  defp collect_follows(identity_id) do
    Hybridsocial.Social.Follow
    |> join(:inner, [f], i in Hybridsocial.Accounts.Identity, on: i.id == f.followee_id)
    |> where([f], f.follower_id == ^identity_id)
    |> select([f, i], %{handle: i.handle})
    |> Repo.all()
  end

  defp collect_followers(identity_id) do
    Hybridsocial.Social.Follow
    |> join(:inner, [f], i in Hybridsocial.Accounts.Identity, on: i.id == f.follower_id)
    |> where([f], f.followee_id == ^identity_id)
    |> select([f, i], %{handle: i.handle})
    |> Repo.all()
  end

  defp collect_blocks(identity_id) do
    Hybridsocial.Social.Block
    |> join(:inner, [b], i in Hybridsocial.Accounts.Identity, on: i.id == b.blocked_id)
    |> where([b], b.blocker_id == ^identity_id)
    |> select([b, i], %{handle: i.handle})
    |> Repo.all()
  end

  defp collect_mutes(identity_id) do
    Hybridsocial.Social.Mute
    |> join(:inner, [m], i in Hybridsocial.Accounts.Identity, on: i.id == m.muted_id)
    |> where([m], m.muter_id == ^identity_id)
    |> select([m, i], %{handle: i.handle})
    |> Repo.all()
  end

  defp collect_bookmarks(identity_id) do
    Hybridsocial.Social.Bookmark
    |> where([b], b.identity_id == ^identity_id)
    |> select([b], %{post_id: b.post_id, inserted_at: b.inserted_at})
    |> Repo.all()
  end

  defp collect_lists(identity_id) do
    Hybridsocial.Social.List
    |> where([l], l.identity_id == ^identity_id)
    |> select([l], %{id: l.id, name: l.name})
    |> Repo.all()
  end
end
