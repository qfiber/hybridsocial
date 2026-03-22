defmodule Hybridsocial.MediaTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Media
  alias Hybridsocial.Media.Storage

  @jpeg_bytes <<0xFF, 0xD8, 0xFF, 0xE0, 0::size(160)>>

  setup do
    # Create an identity for testing
    {:ok, identity} =
      %Hybridsocial.Accounts.Identity{}
      |> Hybridsocial.Accounts.Identity.create_changeset(%{
        "type" => "user",
        "handle" => "mediauser_#{:erlang.unique_integer([:positive])}"
      })
      |> Repo.insert()

    # Write a temp JPEG file
    tmp_path =
      Path.join(System.tmp_dir!(), "test_upload_#{:erlang.unique_integer([:positive])}.jpg")

    File.write!(tmp_path, @jpeg_bytes)

    on_exit(fn ->
      File.rm(tmp_path)
      # Clean up uploads directory
      uploads_dir = Storage.uploads_dir()
      if File.exists?(uploads_dir), do: File.rm_rf!(uploads_dir)
      File.mkdir_p!(uploads_dir)
    end)

    upload = %Plug.Upload{
      path: tmp_path,
      content_type: "image/jpeg",
      filename: "test.jpg"
    }

    %{identity: identity, upload: upload}
  end

  describe "upload/2" do
    test "uploads a valid JPEG file", %{identity: identity, upload: upload} do
      assert {:ok, media} = Media.upload(identity.id, upload)

      assert media.content_type == "image/jpeg"
      assert media.file_size == byte_size(@jpeg_bytes)
      assert media.processing_status == "ready"
      assert media.storage_path != nil
      assert media.identity_id == identity.id
    end

    test "rejects a file with invalid magic bytes", %{identity: identity} do
      tmp_path =
        Path.join(System.tmp_dir!(), "test_invalid_#{:erlang.unique_integer([:positive])}.bin")

      File.write!(tmp_path, <<0x00, 0x00, 0x00, 0x00, 0::size(160)>>)

      upload = %Plug.Upload{
        path: tmp_path,
        content_type: "image/jpeg",
        filename: "fake.jpg"
      }

      assert {:error, :invalid_content_type} = Media.upload(identity.id, upload)
      File.rm(tmp_path)
    end
  end

  describe "upload/3 with alt_text" do
    test "uploads with alt text", %{identity: identity, upload: upload} do
      assert {:ok, media} = Media.upload(identity.id, upload, "A test image")
      assert media.alt_text == "A test image"
    end
  end

  describe "get_media/1" do
    test "returns a media record", %{identity: identity, upload: upload} do
      {:ok, media} = Media.upload(identity.id, upload)
      assert fetched = Media.get_media(media.id)
      assert fetched.id == media.id
    end

    test "returns nil for non-existent ID" do
      assert nil == Media.get_media(Ecto.UUID.generate())
    end

    test "returns nil for soft-deleted media", %{identity: identity, upload: upload} do
      {:ok, media} = Media.upload(identity.id, upload)
      {:ok, _deleted} = Media.delete_media(media.id, identity.id)
      assert nil == Media.get_media(media.id)
    end
  end

  describe "update_alt_text/3" do
    test "updates alt text for owner", %{identity: identity, upload: upload} do
      {:ok, media} = Media.upload(identity.id, upload)
      assert {:ok, updated} = Media.update_alt_text(media.id, identity.id, "Updated alt")
      assert updated.alt_text == "Updated alt"
    end

    test "rejects update by non-owner", %{identity: identity, upload: upload} do
      {:ok, media} = Media.upload(identity.id, upload)

      {:ok, other_identity} =
        %Hybridsocial.Accounts.Identity{}
        |> Hybridsocial.Accounts.Identity.create_changeset(%{
          "type" => "user",
          "handle" => "otheruser_#{:erlang.unique_integer([:positive])}"
        })
        |> Repo.insert()

      assert {:error, :unauthorized} = Media.update_alt_text(media.id, other_identity.id, "Nope")
    end

    test "returns not_found for missing media" do
      assert {:error, :not_found} =
               Media.update_alt_text(Ecto.UUID.generate(), Ecto.UUID.generate(), "alt")
    end
  end

  describe "delete_media/2" do
    test "soft-deletes media for owner", %{identity: identity, upload: upload} do
      {:ok, media} = Media.upload(identity.id, upload)
      assert {:ok, deleted} = Media.delete_media(media.id, identity.id)
      assert deleted.deleted_at != nil
    end

    test "rejects deletion by non-owner", %{identity: identity, upload: upload} do
      {:ok, media} = Media.upload(identity.id, upload)

      {:ok, other_identity} =
        %Hybridsocial.Accounts.Identity{}
        |> Hybridsocial.Accounts.Identity.create_changeset(%{
          "type" => "user",
          "handle" => "deleter"
        })
        |> Repo.insert()

      assert {:error, :unauthorized} = Media.delete_media(media.id, other_identity.id)
    end
  end

  describe "media_url/1" do
    test "returns a URL path", %{identity: identity, upload: upload} do
      {:ok, media} = Media.upload(identity.id, upload)
      url = Media.media_url(media)
      assert url =~ "/uploads/"
      assert url =~ ".jpg"
    end
  end
end
