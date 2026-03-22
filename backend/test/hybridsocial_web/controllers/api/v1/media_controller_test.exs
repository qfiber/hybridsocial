defmodule HybridsocialWeb.Api.V1.MediaControllerTest do
  use HybridsocialWeb.ConnCase, async: true

  alias Hybridsocial.Accounts
  alias Hybridsocial.Media.Storage

  @jpeg_bytes <<0xFF, 0xD8, 0xFF, 0xE0, 0::size(160)>>

  @valid_user_attrs %{
    "handle" => "mediatest",
    "display_name" => "Media Test",
    "email" => "media@example.com",
    "password" => "password123",
    "password_confirmation" => "password123"
  }

  setup %{conn: conn} do
    {:ok, _} = Accounts.register_user(@valid_user_attrs)

    login_conn =
      post(conn, "/api/v1/auth/login", %{
        "email" => "media@example.com",
        "password" => "password123"
      })

    %{"access_token" => token, "identity_id" => identity_id} = json_response(login_conn, 200)
    authed_conn = put_req_header(conn, "authorization", "Bearer #{token}")

    on_exit(fn ->
      uploads_dir = Storage.uploads_dir()
      if File.exists?(uploads_dir), do: File.rm_rf!(uploads_dir)
      File.mkdir_p!(uploads_dir)
    end)

    %{conn: conn, authed_conn: authed_conn, identity_id: identity_id}
  end

  defp create_upload do
    tmp_path =
      Path.join(System.tmp_dir!(), "test_ctrl_#{:erlang.unique_integer([:positive])}.jpg")

    File.write!(tmp_path, @jpeg_bytes)

    upload = %Plug.Upload{
      path: tmp_path,
      content_type: "image/jpeg",
      filename: "test.jpg"
    }

    {upload, tmp_path}
  end

  describe "POST /api/v1/media" do
    test "uploads a file successfully", %{authed_conn: conn} do
      {upload, tmp_path} = create_upload()

      conn = post(conn, "/api/v1/media", %{"file" => upload})
      response = json_response(conn, 201)

      assert response["id"] != nil
      assert response["content_type"] == "image/jpeg"
      assert response["url"] =~ "/uploads/"
      assert response["processing_status"] == "ready"

      File.rm(tmp_path)
    end

    test "uploads with alt text", %{authed_conn: conn} do
      {upload, tmp_path} = create_upload()

      conn = post(conn, "/api/v1/media", %{"file" => upload, "alt_text" => "A nice picture"})
      response = json_response(conn, 201)

      assert response["alt_text"] == "A nice picture"

      File.rm(tmp_path)
    end

    test "rejects upload without file", %{authed_conn: conn} do
      conn = post(conn, "/api/v1/media", %{})
      assert json_response(conn, 400)["error"] == "media.file_required"
    end

    test "rejects upload without auth", %{conn: conn} do
      {upload, tmp_path} = create_upload()

      conn = post(conn, "/api/v1/media", %{"file" => upload})
      assert json_response(conn, 401)["error"] == "auth.unauthorized"

      File.rm(tmp_path)
    end
  end

  describe "GET /api/v1/media/:id" do
    test "returns a media record", %{authed_conn: conn} do
      {upload, tmp_path} = create_upload()

      create_conn = post(conn, "/api/v1/media", %{"file" => upload})
      %{"id" => id} = json_response(create_conn, 201)

      show_conn = get(conn, "/api/v1/media/#{id}")
      response = json_response(show_conn, 200)

      assert response["id"] == id
      assert response["content_type"] == "image/jpeg"

      File.rm(tmp_path)
    end

    test "returns 404 for non-existent media", %{conn: conn} do
      conn = get(conn, "/api/v1/media/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)["error"] == "media.not_found"
    end
  end

  describe "PUT /api/v1/media/:id" do
    test "updates alt text", %{authed_conn: conn} do
      {upload, tmp_path} = create_upload()

      create_conn = post(conn, "/api/v1/media", %{"file" => upload})
      %{"id" => id} = json_response(create_conn, 201)

      update_conn = put(conn, "/api/v1/media/#{id}", %{"alt_text" => "Updated description"})
      response = json_response(update_conn, 200)

      assert response["alt_text"] == "Updated description"

      File.rm(tmp_path)
    end

    test "rejects update without auth", %{conn: conn} do
      conn = put(conn, "/api/v1/media/#{Ecto.UUID.generate()}", %{"alt_text" => "test"})
      assert json_response(conn, 401)["error"] == "auth.unauthorized"
    end
  end
end
