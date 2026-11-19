defmodule Hybridsocial.Social.StoriesTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Media
  alias Hybridsocial.Media.Storage
  alias Hybridsocial.Social.{Stories, Story, StoryReaction, StoryView}

  @jpeg_bytes <<0xFF, 0xD8, 0xFF, 0xE0, 0::size(160)>>

  setup do
    {:ok, author} = register("story_author")
    {:ok, viewer} = register("story_viewer")

    {:ok, _follow} =
      Hybridsocial.Social.follow(viewer.id, author.id)

    tmp_path =
      Path.join(System.tmp_dir!(), "story_#{:erlang.unique_integer([:positive])}.jpg")

    File.write!(tmp_path, @jpeg_bytes)

    upload = %Plug.Upload{
      path: tmp_path,
      content_type: "image/jpeg",
      filename: "story.jpg"
    }

    {:ok, media} = Media.upload(author.id, upload)

    on_exit(fn ->
      File.rm(tmp_path)
      # Delete only the file this test created — don't wipe the whole
      # uploads dir (destroys real dev data and breaks parallel tests).
      _ = Storage.delete(media.storage_path)
    end)

    %{author: author, viewer: viewer, media: media}
  end

  describe "create_story/2" do
    test "creates a story owned by the author", %{author: author, media: media} do
      assert {:ok, story} =
               Stories.create_story(author.id, %{"media_id" => media.id, "duration_hours" => 24})

      assert story.identity_id == author.id
      assert story.media_id == media.id
      assert story.duration_hours == 24
      assert story.expires_at != nil
    end

    test "rejects media owned by another identity", %{viewer: viewer, media: media} do
      assert {:error, :media_not_owned} =
               Stories.create_story(viewer.id, %{"media_id" => media.id, "duration_hours" => 24})
    end

    test "rejects invalid durations", %{author: author, media: media} do
      assert {:error, %Ecto.Changeset{}} =
               Stories.create_story(author.id, %{"media_id" => media.id, "duration_hours" => 12})
    end
  end

  describe "feed_for_viewer/1" do
    test "shows a followed author's active story", %{author: author, viewer: viewer, media: media} do
      {:ok, _story} =
        Stories.create_story(author.id, %{"media_id" => media.id, "duration_hours" => 24})

      feed = Stories.feed_for_viewer(viewer.id)
      assert [%{identity: identity, stories: [story_map]}] = feed
      assert identity.id == author.id
      assert story_map.is_own == false
      assert story_map.viewed == false
    end

    test "puts the viewer's own stories first", %{author: author, media: media} do
      {:ok, _} =
        Stories.create_story(author.id, %{"media_id" => media.id, "duration_hours" => 24})

      # Author views their own feed — their group should be first with is_self: true
      [own | _] = Stories.feed_for_viewer(author.id)
      assert own.is_self == true
    end
  end

  describe "record_view/2 and react/3" do
    test "records view and reaction from a follower", %{
      author: author,
      viewer: viewer,
      media: media
    } do
      {:ok, story} =
        Stories.create_story(author.id, %{"media_id" => media.id, "duration_hours" => 24})

      assert {:ok, :recorded} = Stories.record_view(story.id, viewer.id)
      assert {:ok, :already_viewed} = Stories.record_view(story.id, viewer.id)

      assert {:ok, %StoryReaction{emoji: "🔥"}} =
               Stories.react(story.id, viewer.id, "🔥")

      updated = Repo.get!(Story, story.id)
      assert updated.view_count == 1
      assert updated.reaction_count == 1
    end
  end

  describe "delete_expired/0" do
    test "hard-deletes stories past expires_at and their media", %{
      author: author,
      viewer: viewer,
      media: media
    } do
      {:ok, story} =
        Stories.create_story(author.id, %{"media_id" => media.id, "duration_hours" => 8})

      # Add a view + reaction to make sure cascades don't break delete
      {:ok, :recorded} = Stories.record_view(story.id, viewer.id)
      {:ok, _} = Stories.react(story.id, viewer.id, "❤️")

      past = DateTime.utc_now() |> DateTime.add(-3600, :second)

      {1, _} =
        Repo.update_all(
          from(s in Story, where: s.id == ^story.id),
          set: [expires_at: past]
        )

      assert Stories.delete_expired() >= 1

      refute Repo.get(Story, story.id)
      refute Repo.exists?(from v in StoryView, where: v.story_id == ^story.id)
      refute Repo.exists?(from r in StoryReaction, where: r.story_id == ^story.id)
      refute Media.get_media(media.id)
    end

    test "leaves active stories alone", %{author: author, media: media} do
      {:ok, story} =
        Stories.create_story(author.id, %{"media_id" => media.id, "duration_hours" => 24})

      Stories.delete_expired()
      assert Repo.get(Story, story.id)
    end
  end

  defp register(handle) do
    Hybridsocial.Accounts.register_user(%{
      "handle" => "#{handle}_#{unique_suffix()}",
      "email" => "#{handle}_#{:erlang.unique_integer([:positive])}@test.com",
      "password" => "password123456789",
      "password_confirmation" => "password123456789"
    })
  end
end
