defmodule Hybridsocial.Federation.MigrationTest do
  use Hybridsocial.DataCase

  alias Hybridsocial.Federation.Migration

  defp create_user(handle, email) do
    {:ok, identity} =
      Hybridsocial.Accounts.register_user(%{
        "handle" => handle,
        "email" => email,
        "password" => "password123",
        "password_confirmation" => "password123"
      })

    identity
  end

  describe "add_also_known_as/2" do
    test "adds an alsoKnownAs URI to an identity" do
      user = create_user("akauser1", "aka1@test.com")

      {:ok, updated} = Migration.add_also_known_as(user.id, "https://other.server/actors/123")

      assert "https://other.server/actors/123" in updated.also_known_as
    end

    test "does not duplicate existing URIs" do
      user = create_user("akauser2", "aka2@test.com")

      {:ok, _} = Migration.add_also_known_as(user.id, "https://other.server/actors/123")
      {:ok, updated} = Migration.add_also_known_as(user.id, "https://other.server/actors/123")

      assert length(updated.also_known_as) == 1
    end

    test "can add multiple URIs" do
      user = create_user("akauser3", "aka3@test.com")

      {:ok, _} = Migration.add_also_known_as(user.id, "https://server1.com/actors/1")
      {:ok, updated} = Migration.add_also_known_as(user.id, "https://server2.com/actors/2")

      assert length(updated.also_known_as) == 2
    end

    test "returns error for non-existent identity" do
      assert {:error, :identity_not_found} =
               Migration.add_also_known_as(Ecto.UUID.generate(), "https://example.com/actor")
    end
  end

  describe "remove_also_known_as/2" do
    test "removes an alsoKnownAs URI" do
      user = create_user("rmaka1", "rmaka1@test.com")

      {:ok, _} = Migration.add_also_known_as(user.id, "https://server.com/actors/1")
      {:ok, updated} = Migration.remove_also_known_as(user.id, "https://server.com/actors/1")

      assert updated.also_known_as == []
    end

    test "no-op when URI not present" do
      user = create_user("rmaka2", "rmaka2@test.com")

      {:ok, updated} = Migration.remove_also_known_as(user.id, "https://not-here.com/actors/1")

      assert updated.also_known_as == []
    end
  end

  describe "initiate_migration/2" do
    test "returns error for non-existent identity" do
      assert {:error, :identity_not_found} =
               Migration.initiate_migration(Ecto.UUID.generate(), "https://target.com/actors/1")
    end

    test "returns error for invalid target URL" do
      user = create_user("miguser1", "miguser1@test.com")

      assert {:error, :invalid_target_url} =
               Migration.initiate_migration(user.id, "not-a-url")
    end

    test "returns error for target URL with invalid scheme" do
      user = create_user("miguser2", "miguser2@test.com")

      assert {:error, :invalid_target_url} =
               Migration.initiate_migration(user.id, "ftp://invalid.com/actors/1")
    end
  end

  describe "process_move/1" do
    test "returns error for invalid activity" do
      assert {:error, :invalid_move_activity} = Migration.process_move(%{})
    end

    test "returns error for activity with missing fields" do
      assert {:error, :invalid_move_activity} =
               Migration.process_move(%{"actor" => "https://example.com/actor"})
    end

    test "returns error when actor identity not found" do
      activity = %{
        "type" => "Move",
        "actor" => "https://unknown.server/actors/unknown",
        "target" => "https://new.server/actors/new"
      }

      assert {:error, :identity_not_found} = Migration.process_move(activity)
    end
  end
end
