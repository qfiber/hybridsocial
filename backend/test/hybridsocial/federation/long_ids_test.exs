defmodule Hybridsocial.Federation.LongIdsTest do
  # Remote ids and URLs longer than 255 chars used to raise on insert and
  # 500 the inbox (#267).
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Federation.{Inbox, RemoteActor}
  alias Hybridsocial.Social.{Post, Posts}

  # Shaped like the Bridgy ids seen in production: a percent-encoded Arabic
  # article URL wrapped in a web.brid.gy redirect.
  defp long_url(bytes) do
    prefix = "https://web.brid.gy/r/https://www.alaraby.co.uk/politics/"
    prefix <> String.duplicate("%D8%A7", div(bytes - byte_size(prefix), 6) + 1)
  end

  defp create_activity(object_id) do
    actor = "https://web.brid.gy/r/https://www.alaraby.co.uk/"

    %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "id" => "https://web.brid.gy/r/activities/#{Ecto.UUID.generate()}",
      "type" => "Create",
      "actor" => actor,
      "object" => %{
        "id" => object_id,
        "type" => "Note",
        "content" => "<p>long id</p>",
        "attributedTo" => actor,
        "published" => "2026-11-13T10:00:00Z",
        "to" => ["https://www.w3.org/ns/activitystreams#Public"]
      }
    }
  end

  test "the inbox stores a remote post whose id is longer than 255 chars" do
    id = long_url(400)
    assert byte_size(id) > 255

    assert {:ok, %Post{ap_id: ^id}} = Inbox.process(create_activity(id))
  end

  test "an id over the cap is refused cleanly instead of raising" do
    id = long_url(3000)

    changeset =
      Post.create_changeset(%Post{}, %{
        "identity_id" => Ecto.UUID.generate(),
        "content" => "x",
        "ap_id" => id
      })

    refute changeset.valid?
    assert %{ap_id: [_]} = errors_on(changeset)
  end

  test "a local content warning of 256 to 500 chars saves" do
    identity = create_user("longcw")
    cw = String.duplicate("w", 400)

    assert {:ok, %Post{spoiler_text: ^cw}} =
             Posts.create_post(identity.id, %{"content" => "hi", "spoiler_text" => cw})
  end

  test "remote actor URLs longer than 255 chars are stored, over-cap ones refused" do
    long = long_url(600)

    assert {:ok, actor} =
             %RemoteActor{}
             |> RemoteActor.changeset(%{
               ap_id: long,
               inbox_url: long <> "/inbox",
               avatar_url: long
             })
             |> Repo.insert()

    assert actor.ap_id == long

    refute RemoteActor.changeset(%RemoteActor{}, %{ap_id: long_url(3000)}).valid?
  end
end
