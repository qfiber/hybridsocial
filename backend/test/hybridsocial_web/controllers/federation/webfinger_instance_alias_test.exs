defmodule HybridsocialWeb.Federation.WebfingerInstanceAliasTest do
  # async: false: runtime config (Config.Store) is global.
  use HybridsocialWeb.ConnCase, async: false

  alias Hybridsocial.Config

  setup do
    start_supervised!(Hybridsocial.Config.Store)

    %{
      domain: HybridsocialWeb.Endpoint.host(),
      actor: Hybridsocial.Federation.InstanceActor.ap_id()
    }
  end

  defp finger(conn, acct),
    do: get(conn, "/.well-known/webfinger", %{"resource" => "acct:" <> acct})

  # mastodon.social cached our instance actor under a former host name and
  # re-resolves it by that name: acct:bluestar.social@bassam.social.
  test "answers for a legacy instance-actor username with the current subject", ctx do
    Config.set("instance_actor_legacy_usernames", ["bluestar.social", "arab.place"])

    body = json_response(finger(ctx.conn, "bluestar.social@#{ctx.domain}"), 200)

    assert body["subject"] == "acct:#{ctx.domain}@#{ctx.domain}"
    assert Enum.any?(body["links"], &(&1["rel"] == "self" and &1["href"] == ctx.actor))
  end

  test "accepts the setting as a comma-separated string, case-insensitively", ctx do
    Config.set("instance_actor_legacy_usernames", "Bluestar.Social, arab.place")
    assert json_response(finger(ctx.conn, "ARAB.PLACE@#{ctx.domain}"), 200)
  end

  test "names not in the list still 404", ctx do
    Config.set("instance_actor_legacy_usernames", ["bluestar.social"])
    assert json_response(finger(ctx.conn, "other.social@#{ctx.domain}"), 404)
  end
end
