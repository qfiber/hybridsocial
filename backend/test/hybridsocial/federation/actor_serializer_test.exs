defmodule Hybridsocial.Federation.ActorSerializerTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Federation.ActorSerializer

  defp user_with_metadata(metadata) do
    "actor#{System.unique_integer([:positive])}"
    |> create_user()
    |> Ecto.Changeset.change(metadata: metadata)
    |> Repo.update!()
  end

  defp attachment(metadata), do: ActorSerializer.to_ap(user_with_metadata(metadata))["attachment"]

  test "profile fields federate as PropertyValues" do
    fields = [%{"name" => "Site", "value" => "example.com"}]

    assert attachment(%{"profile_fields" => fields}) == [
             %{"type" => "PropertyValue", "name" => "Site", "value" => "example.com"}
           ]
  end

  test "values are escaped, since receiving servers treat them as HTML" do
    fields = [%{"name" => "Site", "value" => "<script>alert(1)</script>"}]

    assert [%{"value" => value}] = attachment(%{"profile_fields" => fields})
    refute value =~ "<script>"
  end

  test "nothing else in metadata is ever published" do
    assert attachment(%{"posts_per_hour" => 5, "anything" => "else"}) == []
    assert attachment(%{"profile_fields" => []}) == []
  end

  test "malformed rows from before writes were restricted can't break the actor" do
    junk = [
      %{"profile_fields" => "not a list"},
      %{"profile_fields" => [%{"name" => %{"a" => 1}, "value" => [1]}, 5, nil]},
      %{}
    ]

    for metadata <- junk, do: assert(attachment(metadata) == [])
  end

  test "long values from before writes were restricted are clamped" do
    fields = [%{"name" => String.duplicate("n", 500), "value" => String.duplicate("v", 5000)}]

    assert [%{"name" => name, "value" => value}] = attachment(%{"profile_fields" => fields})
    assert String.length(name) == 60
    assert String.length(value) == 280
  end
end
