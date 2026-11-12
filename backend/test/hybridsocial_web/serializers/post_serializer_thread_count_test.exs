defmodule HybridsocialWeb.Serializers.PostSerializerThreadCountTest do
  use Hybridsocial.DataCase, async: true

  import Ecto.Query

  alias Hybridsocial.Social.{Post, Posts}
  alias HybridsocialWeb.Serializers.PostSerializer

  defp user(handle), do: create_user("#{handle}#{System.unique_integer([:positive])}")

  defp post(author, attrs \\ %{}) do
    {:ok, post} = Posts.create_post(author.id, Map.merge(%{"content" => "hello"}, attrs))
    post
  end

  defp reply(author, parent), do: post(author, %{"parent_id" => parent.id})

  defp load(id), do: Post |> Repo.get!(id) |> Repo.preload([:identity, :quote])

  # root
  # ├── a
  # │   ├── a1
  # │   └── a2
  # │       └── a2x
  # └── b
  defp thread do
    author = user("thread")
    root = post(author)
    a = reply(author, root)
    a1 = reply(author, a)
    a2 = reply(author, a)
    _a2x = reply(author, a2)
    _b = reply(author, root)
    %{root: root, a: a, a1: a1}
  end

  test "a root post's thread_reply_count covers the whole conversation" do
    %{root: root} = thread()

    serialized = PostSerializer.serialize(load(root.id))

    # Two direct replies (Mastodon's replies_count semantics stay as-is)…
    assert serialized.reply_count == 2
    # …and five replies in the conversation under it.
    assert serialized.thread_reply_count == 5
  end

  test "serialize_many batches the same totals" do
    %{root: root, a: a, a1: a1} = thread()

    by_id =
      [root.id, a.id, a1.id]
      |> Enum.map(&load/1)
      |> PostSerializer.serialize_many()
      |> Map.new(&{&1.id, &1})

    assert by_id[root.id].thread_reply_count == 5
    # Replies keep their direct count.
    assert by_id[a.id].thread_reply_count == 2
    assert by_id[a1.id].thread_reply_count == 0
  end

  test "deleted replies aren't counted" do
    %{root: root, a1: a1} = thread()

    from(p in Post, where: p.id == ^a1.id)
    |> Repo.update_all(set: [deleted_at: DateTime.utc_now()])

    assert PostSerializer.serialize(load(root.id)).thread_reply_count == 4
  end

  test "a post without replies reports 0" do
    lone = post(user("lone"))
    assert PostSerializer.serialize(load(lone.id)).thread_reply_count == 0
  end
end
