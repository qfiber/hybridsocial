defmodule HybridsocialWeb.Api.V1.AdminTrustLevelTest do
  use HybridsocialWeb.ConnCase, async: true

  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Repo

  setup %{conn: conn} do
    admin = create_admin("trustadmin")
    %{conn: admin_conn(conn, admin), target: create_user("trusttarget")}
  end

  defp set_level(conn, target, level),
    do: post(conn, "/api/v1/admin/users/#{target.id}/trust_level", %{"level" => level})

  test "setting a level pins it", %{conn: conn, target: target} do
    assert json_response(set_level(conn, target, 4), 200)
    assert %Identity{trust_level: 4, trust_level_locked: true} = Repo.get!(Identity, target.id)
  end

  test "\"auto\" unpins and recomputes", %{conn: conn, target: target} do
    set_level(conn, target, 3)
    assert json_response(set_level(conn, target, "auto"), 200)
    # A brand-new account computes back down to 0.
    assert %Identity{trust_level: 0, trust_level_locked: false} = Repo.get!(Identity, target.id)
  end

  test "rejects levels outside 0..4 and junk", %{conn: conn, target: target} do
    for level <- [5, -1, "abc", nil] do
      assert json_response(set_level(conn, target, level), 422)["error"] ==
               "account.trust_level_invalid"
    end
  end
end
