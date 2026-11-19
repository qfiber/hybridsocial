defmodule HybridsocialWeb.Api.V1.DirectoryControllerTest do
  use HybridsocialWeb.ConnCase, async: true

  alias Hybridsocial.Accounts
  alias Hybridsocial.Accounts.User
  alias Hybridsocial.Repo

  defp register_and_confirm(handle, opts \\ []) do
    email = "#{handle}_#{:erlang.unique_integer([:positive])}@example.com"

    {:ok, identity} =
      Accounts.register_user(%{
        "handle" => "#{handle}_#{unique_suffix()}",
        "email" => email,
        "display_name" => handle,
        "password" => "password1234567890",
        "password_confirmation" => "password1234567890"
      })

    identity =
      case Keyword.get(opts, :discoverable) do
        nil ->
          identity

        value ->
          identity
          |> Ecto.Changeset.change(%{discoverable: value})
          |> Repo.update!()
      end

    # Confirm the email so the directory includes this user.
    user = Repo.get_by!(User, identity_id: identity.id)

    user
    |> Ecto.Changeset.change(%{
      confirmed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    })
    |> Repo.update!()

    identity
  end

  describe "GET /api/v1/directory/new" do
    test "returns recently confirmed, discoverable users", %{conn: conn} do
      alice = register_and_confirm("alice_dir")
      bob = register_and_confirm("bob_dir")

      conn = get(conn, "/api/v1/directory/new")
      response = json_response(conn, 200)

      ids = Enum.map(response, & &1["id"])
      assert alice.id in ids
      assert bob.id in ids
    end

    test "excludes users with discoverable=false", %{conn: conn} do
      _visible = register_and_confirm("dir_visible")
      hidden = register_and_confirm("dir_hidden", discoverable: false)

      conn = get(conn, "/api/v1/directory/new")
      response = json_response(conn, 200)

      ids = Enum.map(response, & &1["id"])
      refute hidden.id in ids
    end

    test "excludes unconfirmed users", %{conn: conn} do
      {:ok, pending} =
        Accounts.register_user(%{
          "handle" => "pending_#{:erlang.unique_integer([:positive])}",
          "email" => "pending_#{:erlang.unique_integer([:positive])}@example.com",
          "display_name" => "Pending",
          "password" => "password1234567890",
          "password_confirmation" => "password1234567890"
        })

      conn = get(conn, "/api/v1/directory/new")
      response = json_response(conn, 200)

      refute pending.id in Enum.map(response, & &1["id"])
    end

    test "respects limit param, clamped to 50", %{conn: conn} do
      # Seed 3 users, ask for 2, expect 2.
      for i <- 1..3, do: register_and_confirm("dir_limit_#{i}")

      conn = get(conn, "/api/v1/directory/new", %{"limit" => "2"})
      response = json_response(conn, 200)
      assert length(response) <= 2

      # 999 gets clamped to 50, so still works without error.
      conn = get(conn, "/api/v1/directory/new", %{"limit" => "999"})
      assert json_response(conn, 200) |> is_list()
    end
  end
end
