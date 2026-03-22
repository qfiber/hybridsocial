defmodule Hybridsocial.AccountsTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Accounts

  @valid_user_attrs %{
    "handle" => "testuser",
    "display_name" => "Test User",
    "email" => "test@example.com",
    "password" => "password123",
    "password_confirmation" => "password123"
  }

  describe "register_user/1" do
    test "creates identity and user with valid data" do
      assert {:ok, identity} = Accounts.register_user(@valid_user_attrs)
      assert identity.handle == "testuser"
      assert identity.type == "user"
      assert identity.display_name == "Test User"
      assert identity.user.email == "test@example.com"
      assert identity.user.password_hash != nil
      assert identity.user.confirmation_token != nil
      assert identity.public_key != nil
      assert identity.private_key != nil
      assert identity.ap_actor_url != nil
    end

    test "rejects duplicate handle" do
      assert {:ok, _} = Accounts.register_user(@valid_user_attrs)

      assert {:error, changeset} =
               Accounts.register_user(%{@valid_user_attrs | "email" => "other@example.com"})

      assert %{handle: ["has already been taken"]} = errors_on(changeset)
    end

    test "rejects duplicate email" do
      assert {:ok, _} = Accounts.register_user(@valid_user_attrs)

      assert {:error, changeset} =
               Accounts.register_user(%{@valid_user_attrs | "handle" => "other"})

      assert %{email: ["has already been taken"]} = errors_on(changeset)
    end

    test "rejects invalid handle characters" do
      attrs = %{@valid_user_attrs | "handle" => "bad handle!"}
      assert {:error, changeset} = Accounts.register_user(attrs)
      assert %{handle: [_]} = errors_on(changeset)
    end

    test "rejects short password" do
      attrs = %{@valid_user_attrs | "password" => "short", "password_confirmation" => "short"}
      assert {:error, changeset} = Accounts.register_user(attrs)
      assert %{password: [_]} = errors_on(changeset)
    end

    test "rejects mismatched password confirmation" do
      attrs = %{@valid_user_attrs | "password_confirmation" => "different"}
      assert {:error, changeset} = Accounts.register_user(attrs)
      assert %{password_confirmation: [_]} = errors_on(changeset)
    end
  end

  describe "authenticate_user/2" do
    setup do
      {:ok, identity} = Accounts.register_user(@valid_user_attrs)
      %{identity: identity}
    end

    test "succeeds with correct credentials" do
      assert {:ok, user} = Accounts.authenticate_user("test@example.com", "password123")
      assert user.email == "test@example.com"
    end

    test "fails with wrong password" do
      assert {:error, :invalid_credentials} =
               Accounts.authenticate_user("test@example.com", "wrong")
    end

    test "fails with non-existent email" do
      assert {:error, :invalid_credentials} =
               Accounts.authenticate_user("nonexistent@example.com", "password123")
    end

    test "fails for suspended account", %{identity: identity} do
      {:ok, _} =
        identity
        |> Hybridsocial.Accounts.Identity.suspend_changeset()
        |> Hybridsocial.Repo.update()

      assert {:error, :account_suspended} =
               Accounts.authenticate_user("test@example.com", "password123")
    end
  end

  describe "confirm_user/1" do
    test "confirms with valid token" do
      {:ok, identity} = Accounts.register_user(@valid_user_attrs)
      token = identity.user.confirmation_token

      assert {:ok, user} = Accounts.confirm_user(token)
      assert user.confirmed_at != nil
      assert user.confirmation_token == nil
    end

    test "fails with invalid token" do
      assert {:error, :invalid_token} = Accounts.confirm_user("bogus_token")
    end
  end

  describe "get_identity/1" do
    test "returns identity by id" do
      {:ok, identity} = Accounts.register_user(@valid_user_attrs)
      assert found = Accounts.get_identity(identity.id)
      assert found.id == identity.id
    end

    test "returns nil for soft-deleted identity" do
      {:ok, identity} = Accounts.register_user(@valid_user_attrs)
      {:ok, _} = Accounts.soft_delete_identity(identity)
      assert Accounts.get_identity(identity.id) == nil
    end
  end

  describe "update_identity/2" do
    test "updates profile fields" do
      {:ok, identity} = Accounts.register_user(@valid_user_attrs)

      assert {:ok, updated} =
               Accounts.update_identity(identity, %{
                 "display_name" => "New Name",
                 "bio" => "Hello world"
               })

      assert updated.display_name == "New Name"
      assert updated.bio == "Hello world"
    end
  end

  describe "change_handle/2" do
    test "changes handle and reserves old one" do
      {:ok, identity} = Accounts.register_user(@valid_user_attrs)

      assert {:ok, %{identity: updated}} = Accounts.change_handle(identity, "newhandle")
      assert updated.handle == "newhandle"
      assert Accounts.handle_reserved?("testuser") == true
    end
  end
end
