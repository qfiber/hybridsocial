defmodule Hybridsocial.Media.StorageTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Media.Storage

  setup do
    # Clean up any test files after each test
    on_exit(fn ->
      uploads_dir = Storage.uploads_dir()
      if File.exists?(uploads_dir), do: File.rm_rf!(uploads_dir)
    end)

    :ok
  end

  # ---------------------------------------------------------------------------
  # Local Storage
  # ---------------------------------------------------------------------------

  describe "store_local/2" do
    test "stores a file and returns the relative path" do
      # Create a temp file to simulate an upload
      tmp_path = Path.join(System.tmp_dir!(), "test_upload_#{System.unique_integer([:positive])}.txt")
      File.write!(tmp_path, "test content")

      upload = %Plug.Upload{
        path: tmp_path,
        content_type: "image/png",
        filename: "test.png"
      }

      assert {:ok, storage_path} = Storage.store_local(upload, "some-identity-id")
      assert String.starts_with?(storage_path, "images/")
      assert String.ends_with?(storage_path, ".png")

      # Verify the file was actually stored
      full = Path.join(Storage.uploads_dir(), storage_path)
      assert File.exists?(full)
      assert File.read!(full) == "test content"

      File.rm(tmp_path)
    end

    test "creates correct directory structure" do
      tmp_path = Path.join(System.tmp_dir!(), "test_upload_#{System.unique_integer([:positive])}.txt")
      File.write!(tmp_path, "video content")

      upload = %Plug.Upload{
        path: tmp_path,
        content_type: "video/mp4",
        filename: "test.mp4"
      }

      assert {:ok, storage_path} = Storage.store_local(upload, "some-identity-id")
      assert String.starts_with?(storage_path, "videos/")
      assert String.ends_with?(storage_path, ".mp4")

      File.rm(tmp_path)
    end
  end

  describe "delete_local/1" do
    test "deletes a stored file" do
      tmp_path = Path.join(System.tmp_dir!(), "test_upload_#{System.unique_integer([:positive])}.txt")
      File.write!(tmp_path, "test content")

      upload = %Plug.Upload{
        path: tmp_path,
        content_type: "image/jpeg",
        filename: "test.jpg"
      }

      {:ok, storage_path} = Storage.store_local(upload, "some-identity-id")

      full = Path.join(Storage.uploads_dir(), storage_path)
      assert File.exists?(full)

      assert :ok = Storage.delete_local(storage_path)
      refute File.exists?(full)

      File.rm(tmp_path)
    end

    test "returns :ok when file does not exist" do
      assert :ok = Storage.delete_local("nonexistent/path.jpg")
    end
  end

  # ---------------------------------------------------------------------------
  # URL generation
  # ---------------------------------------------------------------------------

  describe "url/1" do
    test "returns URL with /uploads/ prefix for local storage" do
      url = Storage.url("images/2026/03/test.png")
      assert url =~ "/uploads/images/2026/03/test.png"
    end
  end

  # ---------------------------------------------------------------------------
  # Storage backend
  # ---------------------------------------------------------------------------

  describe "storage_backend/0" do
    test "defaults to local" do
      assert Storage.storage_backend() == "local"
    end
  end
end
