defmodule HybridsocialWeb.Plugs.RequireSudoTest do
  use HybridsocialWeb.ConnCase, async: true

  import Ecto.Query

  alias Hybridsocial.Auth.OAuthToken
  alias Hybridsocial.Auth.Token
  alias Hybridsocial.Repo

  @path "/api/v1/admin/pending_accounts"

  setup %{conn: conn} do
    admin = create_user("sudoadmin", "sudoadmin@test.com") |> make_admin()
    conn = admin_conn(conn, admin)
    ["Bearer " <> token] = Plug.Conn.get_req_header(conn, "authorization")

    %{conn: conn, token_hash: Token.hash_token(token)}
  end

  defp set_sudo_until(token_hash, until) do
    OAuthToken
    |> where([t], t.token_hash == ^token_hash)
    |> Repo.update_all(set: [sudo_until: until])
  end

  defp sudo_until(token_hash) do
    OAuthToken
    |> where([t], t.token_hash == ^token_hash)
    |> select([t], t.sudo_until)
    |> Repo.one()
  end

  defp in_seconds(seconds), do: DateTime.add(DateTime.utc_now(), seconds, :second)

  test "a normal request extends the window and reports the new expiry", ctx do
    before = in_seconds(60)
    set_sudo_until(ctx.token_hash, before)

    conn = get(ctx.conn, @path)

    assert conn.status == 200
    until = sudo_until(ctx.token_hash)
    assert DateTime.compare(until, before) == :gt
    assert get_resp_header(conn, "x-sudo-expires-at") == [DateTime.to_iso8601(until)]
  end

  test "a passive request leaves the window alone and reports the current expiry", ctx do
    set_sudo_until(ctx.token_hash, in_seconds(60))
    before = sudo_until(ctx.token_hash)

    conn = ctx.conn |> put_req_header("x-sudo-passive", "1") |> get(@path)

    assert conn.status == 200
    assert sudo_until(ctx.token_hash) == before
    assert get_resp_header(conn, "x-sudo-expires-at") == [DateTime.to_iso8601(before)]
  end

  test "a passive request is still refused once the window has lapsed", ctx do
    set_sudo_until(ctx.token_hash, in_seconds(-1))

    conn = ctx.conn |> put_req_header("x-sudo-passive", "1") |> get(@path)

    assert %{"error" => "auth.sudo_required"} = json_response(conn, 403)
    assert get_resp_header(conn, "x-sudo-expires-at") == []
  end

  test "a lapsed window is not revived by a normal request", ctx do
    expired = in_seconds(-1)
    set_sudo_until(ctx.token_hash, expired)

    conn = get(ctx.conn, @path)

    assert json_response(conn, 403)["error"] == "auth.sudo_required"
    assert DateTime.compare(sudo_until(ctx.token_hash), DateTime.utc_now()) == :lt
  end
end
