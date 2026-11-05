defmodule HybridsocialWeb.Api.V1.SuspendedThreadTest do
  use HybridsocialWeb.ConnCase

  import Ecto.Query

  alias Hybridsocial.Accounts
  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Federation
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.Posts

  defp post_by(identity, content, parent \\ nil) do
    attrs = %{"content" => content}
    attrs = if parent, do: Map.put(attrs, "parent_id", parent.id), else: attrs
    {:ok, post} = Posts.create_post(identity.id, attrs)
    post
  end

  defp context(conn, post) do
    conn |> get("/api/v1/statuses/#{post.id}/context") |> json_response(200)
  end

  defp ids(posts), do: Enum.map(posts, & &1["id"])

  setup %{conn: conn} do
    author = create_user("st_author")
    spammer = create_user("st_spammer")
    root = post_by(author, "root")
    reply = post_by(spammer, "bad reply", root)

    %{conn: conn, author: author, spammer: spammer, root: root, reply: reply}
  end

  test "a suspended author's reply is hidden", ctx do
    assert ctx.reply.id in ids(context(ctx.conn, ctx.root)["descendants"])

    {:ok, _} = Accounts.suspend_identity(ctx.spammer)

    refute ctx.reply.id in ids(context(ctx.conn, ctx.root)["descendants"])
  end

  test "a reply from a suspended domain is hidden", ctx do
    {1, _} =
      Repo.update_all(from(i in Identity, where: i.id == ^ctx.spammer.id),
        set: [is_local: false, ap_actor_url: "https://evil.example/users/x"]
      )

    {:ok, _} = Federation.set_instance_policy("evil.example", "suspend", nil, nil)

    refute ctx.reply.id in ids(context(ctx.conn, ctx.root)["descendants"])
  end

  test "other replies stay, and a reply to a hidden one keeps its place", ctx do
    other = create_user("st_other")
    fine = post_by(other, "fine reply", ctx.root)
    nested = post_by(other, "answering the spam", ctx.reply)

    {:ok, _} = Accounts.suspend_identity(ctx.spammer)

    descendants = context(ctx.conn, ctx.root)["descendants"]
    assert fine.id in ids(descendants)
    assert nested.id in ids(descendants)
    # The hidden reply's id is a tombstone, with none of its content.
    assert %{} = tombstone = Enum.find(descendants, &(&1["id"] == ctx.reply.id))
    refute tombstone["content"] == "bad reply"
  end

  test "a suspended author's ancestor is replaced by a tombstone", ctx do
    other = create_user("st_child")
    child = post_by(other, "answering the spam", ctx.reply)

    {:ok, _} = Accounts.suspend_identity(ctx.spammer)

    ancestors = context(ctx.conn, child)["ancestors"]
    assert ctx.root.id in ids(ancestors)
    refute Enum.any?(ancestors, &(&1["content"] == "bad reply"))
  end

  test "a suspended author's own post has no readable thread", ctx do
    {:ok, _} = Accounts.suspend_identity(ctx.spammer)

    assert ctx.conn |> get("/api/v1/statuses/#{ctx.reply.id}/context") |> json_response(404)
  end

  test "staff still see the reply, so they can review it", ctx do
    {:ok, _} = Accounts.suspend_identity(ctx.spammer)
    staff = admin_conn(ctx.conn, create_admin("st_staff"))

    assert ctx.reply.id in ids(context(staff, ctx.root)["descendants"])
    assert staff |> get("/api/v1/statuses/#{ctx.reply.id}/context") |> json_response(200)
  end

  test "a regular logged-in viewer doesn't see the reply either", ctx do
    {:ok, _} = Accounts.suspend_identity(ctx.spammer)
    viewer = auth_conn(ctx.conn, create_user("st_viewer"))

    refute ctx.reply.id in ids(context(viewer, ctx.root)["descendants"])
  end
end
