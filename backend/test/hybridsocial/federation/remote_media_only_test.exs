defmodule Hybridsocial.Federation.RemoteMediaOnlyTest do
  # An image-only remote Note (no text) used to fail the "content can't be
  # blank" check and be dropped: the inbox stored every Note as a text post.
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Federation.Inbox
  alias Hybridsocial.Social.Post

  @actor "https://media.example/users/painter"

  defp note(id, extra) do
    Map.merge(
      %{
        "id" => id,
        "type" => "Note",
        "content" => "",
        "attributedTo" => @actor,
        # Relative to now: remote posts get a 24h edit window from `published`,
        # so a fixed date made the edit test fail a day after it was written.
        "published" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "to" => ["https://www.w3.org/ns/activitystreams#Public"]
      },
      extra
    )
  end

  defp create(object) do
    %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "id" => object["id"] <> "/activity",
      "type" => "Create",
      "actor" => @actor,
      "object" => object
    }
  end

  @image %{
    "type" => "Document",
    "mediaType" => "image/png",
    "url" => "https://media.example/files/cat.png"
  }

  test "stores an image-only Note with its media" do
    object = note("https://media.example/objects/img-only", %{"attachment" => [@image]})

    assert {:ok, %Post{} = post} = Inbox.process(create(object))
    post = Repo.preload(post, :media_attachments)
    assert [_] = post.media_attachments
  end

  test "accepts a single attachment given as a map, not a list" do
    object = note("https://media.example/objects/img-map", %{"attachment" => @image})
    assert {:ok, %Post{}} = Inbox.process(create(object))
  end

  test "still rejects a Note with neither text nor usable media" do
    object =
      note("https://media.example/objects/empty", %{"attachment" => [%{"type" => "Document"}]})

    assert {:error, %Ecto.Changeset{}} = Inbox.process(create(object))
  end

  test "a remote edit can clear the caption of a media post" do
    id = "https://media.example/objects/captioned"
    object = note(id, %{"content" => "<p>a cat</p>", "attachment" => [@image]})
    assert {:ok, _} = Inbox.process(create(object))

    update = %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "id" => id <> "/update",
      "type" => "Update",
      "actor" => @actor,
      "object" => Map.put(object, "content", "")
    }

    # Before the fix this was refused with "content can't be blank".
    assert {:ok, %Post{content: nil}} = Inbox.process(update)
  end
end
