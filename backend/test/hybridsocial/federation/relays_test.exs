defmodule Hybridsocial.Federation.RelaysTest do
  use Hybridsocial.DataCase, async: false

  alias Hybridsocial.Federation.Relays

  defp create_admin(handle, email) do
    {:ok, identity} =
      Hybridsocial.Accounts.register_user(%{
        "handle" => handle,
        "email" => email,
        "password" => "Password123!!",
        "password_confirmation" => "Password123!!"
      })

    identity
    |> Ecto.Changeset.change(is_admin: true)
    |> Hybridsocial.Repo.update!()
  end

  describe "subscribe_to_relay/2" do
    test "creates a relay with pending status" do
      admin = create_admin("relay_admin", "relay_admin@example.com")

      assert {:ok, relay} =
               Relays.subscribe_to_relay("https://relay.example/inbox", admin.id)

      assert relay.inbox_url == "https://relay.example/inbox"
      assert relay.status == "pending"
    end

    test "rejects duplicate inbox URLs" do
      admin = create_admin("relay_dup_admin", "relay_dup_admin@example.com")

      {:ok, _} = Relays.subscribe_to_relay("https://relay2.example/inbox", admin.id)
      assert {:error, _} = Relays.subscribe_to_relay("https://relay2.example/inbox", admin.id)
    end
  end

  describe "unsubscribe_from_relay/2" do
    test "removes the relay" do
      admin = create_admin("relay_unsub", "relay_unsub@example.com")
      {:ok, relay} = Relays.subscribe_to_relay("https://relay3.example/inbox", admin.id)

      assert {:ok, _} = Relays.unsubscribe_from_relay(relay.id, admin.id)
      assert Relays.get_relay(relay.id) == nil
    end

    test "returns error for non-existent relay" do
      admin = create_admin("relay_missing", "relay_missing@example.com")
      fake_id = Ecto.UUID.generate()

      assert {:error, :not_found} = Relays.unsubscribe_from_relay(fake_id, admin.id)
    end
  end

  describe "list_relays/0" do
    test "returns all relays" do
      admin = create_admin("relay_list", "relay_list@example.com")
      {:ok, _} = Relays.subscribe_to_relay("https://relay4.example/inbox", admin.id)
      {:ok, _} = Relays.subscribe_to_relay("https://relay5.example/inbox", admin.id)

      relays = Relays.list_relays()
      assert length(relays) >= 2
    end
  end

  describe "accept_relay/1" do
    test "marks relay as accepted by domain" do
      admin = create_admin("relay_accept", "relay_accept@example.com")
      {:ok, _} = Relays.subscribe_to_relay("https://relay6.example/inbox", admin.id)

      assert {:ok, relay} = Relays.accept_relay("relay6.example")
      assert relay.status == "accepted"
    end

    test "returns error for unknown domain" do
      assert {:error, :not_found} = Relays.accept_relay("unknown.example")
    end
  end

  describe "process_relay_announce/1" do
    test "returns :ok (stub)" do
      assert :ok = Relays.process_relay_announce(%{"type" => "Announce"})
    end
  end
end
