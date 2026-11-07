defmodule HybridsocialWeb.Serializers.PostSerializerQuoteTest do
  use Hybridsocial.DataCase, async: true

  import Ecto.Query

  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Social
  alias Hybridsocial.Social.{Post, Posts}
  alias HybridsocialWeb.Serializers.PostSerializer

  setup do
    %{
      viewer: user("viewer"),
      quoter: user("quoter"),
      author: user("author")
    }
  end

  defp user(handle), do: create_user("#{handle}#{System.unique_integer([:positive])}")

  defp post(author, attrs \\ %{}) do
    {:ok, post} = Posts.create_post(author.id, Map.merge(%{"content" => "hello"}, attrs))
    post
  end

  defp quoting(quoter, quoted) do
    outer = post(quoter)
    from(p in Post, where: p.id == ^outer.id) |> Repo.update_all(set: [quote_id: quoted.id])
    outer.id
  end

  defp set_post(post, fields) do
    from(p in Post, where: p.id == ^post.id) |> Repo.update_all(set: fields)
  end

  defp set_identity(identity, fields) do
    from(i in Identity, where: i.id == ^identity.id) |> Repo.update_all(set: fields)
  end

  defp load(id), do: Post |> Repo.get!(id) |> Repo.preload([:identity, :quote])

  # Every rule has to hold through both ways a post gets serialized.
  defp both_paths(id, opts) do
    [
      hd(PostSerializer.serialize_many([load(id)], opts)),
      PostSerializer.serialize(load(id), opts)
    ]
  end

  defp assert_visible(id, quoted, opts) do
    for result <- both_paths(id, opts) do
      assert result.quote.id == quoted.id
      assert result.quote_unavailable == false
    end
  end

  defp assert_unavailable(id, opts) do
    for result <- both_paths(id, opts) do
      assert result.quote == nil
      assert result.quote_unavailable == true
    end
  end

  test "a public quote is shown to anyone", %{viewer: viewer, quoter: quoter, author: author} do
    quoted = post(author)
    id = quoting(quoter, quoted)

    assert_visible(id, quoted, current_identity_id: viewer.id)
    assert_visible(id, quoted, [])
  end

  test "a post with no quote isn't marked unavailable", %{viewer: viewer, quoter: quoter} do
    for result <- both_paths(post(quoter).id, current_identity_id: viewer.id) do
      assert result.quote == nil
      assert result.quote_unavailable == false
    end
  end

  describe "the quoted post's own visibility" do
    test "quoting a followers-only post doesn't let anyone read it",
         %{viewer: viewer, quoter: quoter, author: author} do
      quoted = post(author, %{"visibility" => "followers"})
      id = quoting(quoter, quoted)

      assert_unavailable(id, current_identity_id: viewer.id)
      assert_unavailable(id, [])
      assert_unavailable(id, current_identity_id: quoter.id)

      {:ok, _} = Social.follow(viewer.id, author.id)
      assert_visible(id, quoted, current_identity_id: viewer.id)
    end

    test "a direct post stays private, even from staff",
         %{quoter: quoter, author: author} do
      quoted = post(author, %{"visibility" => "direct"})
      id = quoting(quoter, quoted)

      assert_unavailable(id, current_identity_id: create_admin("quoteadmin1").id)
      assert_unavailable(id, current_identity_id: quoter.id)
      assert_visible(id, quoted, current_identity_id: author.id)
    end
  end

  describe "moderation" do
    setup %{quoter: quoter, author: author} do
      quoted = post(author)
      %{quoted: quoted, id: quoting(quoter, quoted)}
    end

    test "a deleted quote is unavailable to everyone, including its author and staff",
         %{id: id, quoted: quoted, viewer: viewer, author: author} do
      set_post(quoted, deleted_at: DateTime.utc_now())

      assert_unavailable(id, current_identity_id: viewer.id)
      assert_unavailable(id, current_identity_id: author.id)
      assert_unavailable(id, current_identity_id: create_admin("quoteadmin2").id)
    end

    test "a hidden quote is unavailable, except to its author and staff",
         %{id: id, quoted: quoted, viewer: viewer, author: author} do
      set_post(quoted, hidden_at: DateTime.utc_now())

      assert_unavailable(id, current_identity_id: viewer.id)
      assert_unavailable(id, [])
      assert_visible(id, quoted, current_identity_id: author.id)
      assert_visible(id, quoted, current_identity_id: create_admin("quoteadmin3").id)
    end

    test "a suspended author's quote is unavailable, except to staff",
         %{id: id, quoted: quoted, viewer: viewer, author: author} do
      set_identity(author, is_suspended: true)

      assert_unavailable(id, current_identity_id: viewer.id)
      assert_visible(id, quoted, current_identity_id: create_admin("quoteadmin4").id)
    end

    test "a shadow-banned author's quote is shown only to them",
         %{id: id, quoted: quoted, viewer: viewer, author: author} do
      set_identity(author, is_shadow_banned: true)

      assert_unavailable(id, current_identity_id: viewer.id)
      assert_visible(id, quoted, current_identity_id: author.id)
    end

    test "a silenced author's quote is shown only to followers",
         %{id: id, quoted: quoted, viewer: viewer, author: author} do
      set_identity(author, is_silenced: true)

      assert_unavailable(id, current_identity_id: viewer.id)
      assert_unavailable(id, [])

      {:ok, _} = Social.follow(viewer.id, author.id)
      assert_visible(id, quoted, current_identity_id: viewer.id)
    end
  end

  describe "the viewer's own choices" do
    setup %{quoter: quoter, author: author} do
      quoted = post(author)
      %{quoted: quoted, id: quoting(quoter, quoted)}
    end

    test "a block applies in both directions", %{id: id, viewer: viewer, author: author} do
      {:ok, _} = Social.block(viewer.id, author.id)
      assert_unavailable(id, current_identity_id: viewer.id)

      other = user("other")
      {:ok, _} = Social.block(author.id, other.id)
      assert_unavailable(id, current_identity_id: other.id)
    end

    test "a mute applies", %{id: id, viewer: viewer, author: author} do
      {:ok, _} = Social.mute(viewer.id, author.id)
      assert_unavailable(id, current_identity_id: viewer.id)
    end

    test "a blocked domain applies", %{id: id, viewer: viewer, author: author} do
      set_identity(author, is_local: false, ap_actor_url: "https://blocked.example/users/1")

      Repo.insert_all("user_domain_blocks", [
        %{
          id: Ecto.UUID.dump!(Ecto.UUID.generate()),
          identity_id: Ecto.UUID.dump!(viewer.id),
          domain: "blocked.example",
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        }
      ])

      assert_unavailable(id, current_identity_id: viewer.id)
    end
  end

  describe "nested quotes" do
    test "each level is checked on its own", %{viewer: viewer, quoter: quoter, author: author} do
      inner = post(author)
      middle_id = quoting(user("middle"), inner)
      outer_id = quoting(quoter, Repo.get!(Post, middle_id))

      for result <- both_paths(outer_id, current_identity_id: viewer.id) do
        assert result.quote.id == middle_id
        assert result.quote.quote.id == inner.id
      end

      set_post(inner, hidden_at: DateTime.utc_now())

      for result <- both_paths(outer_id, current_identity_id: viewer.id) do
        assert result.quote.id == middle_id
        assert result.quote_unavailable == false
        assert result.quote.quote == nil
        assert result.quote.quote_unavailable == true
      end
    end
  end

  test "a page mixes shown and unavailable quotes correctly",
       %{viewer: viewer, quoter: quoter, author: author} do
    fine = post(author)
    hidden = post(author)
    set_post(hidden, hidden_at: DateTime.utc_now())
    private = post(author, %{"visibility" => "followers"})

    ids = [
      quoting(quoter, fine),
      quoting(quoter, hidden),
      quoting(quoter, private),
      post(quoter).id
    ]

    results =
      ids
      |> Enum.map(&load/1)
      |> PostSerializer.serialize_many(current_identity_id: viewer.id)

    assert [fine.id, nil, nil, nil] == Enum.map(results, &(&1.quote && &1.quote.id))
    assert [false, true, true, false] == Enum.map(results, & &1.quote_unavailable)
  end

  test "serialize_many loads quotes the caller didn't preload",
       %{viewer: viewer, quoter: quoter, author: author} do
    quoted = post(author)
    id = quoting(quoter, quoted)
    bare = Post |> Repo.get!(id) |> Repo.preload(:identity)

    [result] = PostSerializer.serialize_many([bare], current_identity_id: viewer.id)

    assert result.quote.id == quoted.id
  end

  describe "the anonymous snapshot, once overlaid for a viewer" do
    # The prewarmed feed is stored as JSON, so it comes back with string keys.
    defp snapshot(ids) do
      ids
      |> Enum.map(&load/1)
      |> PostSerializer.serialize_many(current_identity_id: nil)
      |> Jason.encode!()
      |> Jason.decode!()
    end

    test "only ever holds quotes fit for anyone", %{quoter: quoter, author: author} do
      id = quoting(quoter, post(author, %{"visibility" => "followers"}))

      assert [%{"quote" => nil, "quote_unavailable" => true}] = snapshot([id])
    end

    test "drops a quote by someone this viewer blocked or muted",
         %{viewer: viewer, quoter: quoter, author: author} do
      quoted = post(author)
      id = quoting(quoter, quoted)
      data = snapshot([id])

      assert [%{"quote" => %{"id" => quoted_id}}] =
               PostSerializer.apply_viewer_state(data, viewer.id)

      assert quoted_id == quoted.id

      {:ok, _} = Social.mute(viewer.id, author.id)

      assert [%{"quote" => nil, "quote_unavailable" => true}] =
               PostSerializer.apply_viewer_state(data, viewer.id)
    end

    test "drops a nested quote by someone this viewer blocked",
         %{viewer: viewer, quoter: quoter, author: author} do
      inner = post(author)
      middle_id = quoting(user("middle"), inner)
      outer_id = quoting(quoter, Repo.get!(Post, middle_id))
      data = snapshot([outer_id])

      {:ok, _} = Social.block(viewer.id, author.id)

      assert [%{"quote" => %{"id" => ^middle_id} = middle}] =
               PostSerializer.apply_viewer_state(data, viewer.id)

      assert middle["quote"] == nil
      assert middle["quote_unavailable"] == true
    end
  end
end
