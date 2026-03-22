defmodule Hybridsocial.PortabilityTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Portability

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

  describe "request_export/1" do
    test "creates a pending export" do
      identity = create_user("exportuser", "export@test.com")

      assert {:ok, export} = Portability.request_export(identity.id)
      assert export.status == "pending"
      assert export.requested_at != nil
    end
  end

  describe "get_exports/1" do
    test "returns exports for identity" do
      identity = create_user("exports1", "exports1@test.com")
      {:ok, _} = Portability.request_export(identity.id)
      {:ok, _} = Portability.request_export(identity.id)

      exports = Portability.get_exports(identity.id)
      assert length(exports) == 2
    end

    test "returns empty list when no exports" do
      identity = create_user("noexports", "noexports@test.com")
      assert Portability.get_exports(identity.id) == []
    end
  end

  describe "get_export/2" do
    test "returns specific export" do
      identity = create_user("getexp", "getexp@test.com")
      {:ok, export} = Portability.request_export(identity.id)

      found = Portability.get_export(export.id, identity.id)
      assert found.id == export.id
    end

    test "returns nil for wrong identity" do
      identity1 = create_user("getexp1", "getexp1@test.com")
      identity2 = create_user("getexp2", "getexp2@test.com")
      {:ok, export} = Portability.request_export(identity1.id)

      assert Portability.get_export(export.id, identity2.id) == nil
    end
  end

  describe "generate_export/1" do
    test "generates export file" do
      identity = create_user("genexp", "genexp@test.com")
      {:ok, export} = Portability.request_export(identity.id)

      assert {:ok, completed} = Portability.generate_export(export.id)
      assert completed.status == "completed"
      assert completed.file_path != nil
      assert completed.file_size > 0
      assert completed.completed_at != nil

      # Cleanup
      File.rm(completed.file_path)
    end

    test "returns error for non-existent export" do
      assert {:error, :not_found} = Portability.generate_export(Ecto.UUID.generate())
    end
  end

  describe "request_deletion/2" do
    test "schedules deletion 30 days out" do
      identity = create_user("deluser", "del@test.com")

      assert {:ok, deletion} = Portability.request_deletion(identity.id, "leaving")
      assert deletion.reason == "leaving"
      assert deletion.scheduled_for != nil

      # Should be approximately 30 days from now
      diff = DateTime.diff(deletion.scheduled_for, DateTime.utc_now(), :second)
      assert diff > 29 * 24 * 3600
      assert diff <= 30 * 24 * 3600
    end
  end

  describe "cancel_deletion/1" do
    test "cancels a scheduled deletion" do
      identity = create_user("canceldeluser", "canceldel@test.com")
      {:ok, _} = Portability.request_deletion(identity.id)

      assert {:ok, cancelled} = Portability.cancel_deletion(identity.id)
      assert cancelled.cancelled_at != nil
    end

    test "returns error when no active deletion" do
      identity = create_user("nocanceldel", "nocanceldel@test.com")
      assert {:error, :not_found} = Portability.cancel_deletion(identity.id)
    end
  end

  describe "get_deletion/1" do
    test "returns active deletion" do
      identity = create_user("getdel", "getdel@test.com")
      {:ok, _} = Portability.request_deletion(identity.id)

      deletion = Portability.get_deletion(identity.id)
      assert deletion != nil
    end

    test "returns nil when no active deletion" do
      identity = create_user("nogetdel", "nogetdel@test.com")
      assert Portability.get_deletion(identity.id) == nil
    end

    test "returns nil when deletion is cancelled" do
      identity = create_user("cancelgetdel", "cancelgetdel@test.com")
      {:ok, _} = Portability.request_deletion(identity.id)
      {:ok, _} = Portability.cancel_deletion(identity.id)

      assert Portability.get_deletion(identity.id) == nil
    end
  end

  describe "execute_deletion/1" do
    test "executes a deletion" do
      identity = create_user("execdeluser", "execdel@test.com")
      {:ok, deletion} = Portability.request_deletion(identity.id)

      assert {:ok, executed} = Portability.execute_deletion(deletion.id)
      assert executed.executed_at != nil

      # Identity should be soft-deleted
      assert Hybridsocial.Accounts.get_identity(identity.id) == nil
    end

    test "returns error for non-existent deletion" do
      assert {:error, :not_found} = Portability.execute_deletion(Ecto.UUID.generate())
    end
  end
end
