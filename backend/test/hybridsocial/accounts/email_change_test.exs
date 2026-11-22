defmodule Hybridsocial.Accounts.EmailChangeTest do
  # async: false — Swoosh's test mailbox is shared per process tree.
  use Hybridsocial.DataCase, async: false
  import Swoosh.TestAssertions

  alias Hybridsocial.Accounts
  alias Hybridsocial.Accounts.User

  setup do
    identity = create_user("mailmover", "old@example.com")
    # Drop the registration confirmation create_user sends.
    assert_email_sent(subject: ~r/confirm your email address/)
    %{identity: identity}
  end

  defp user(identity), do: Repo.get_by!(User, identity_id: identity.id)

  # The token only travels in the email; pull it out of the confirm link.
  defp token_from_email do
    assert_email_sent(fn email ->
      if email.subject =~ "confirm your new email" do
        send(
          self(),
          {:token, Regex.run(~r/token=([A-Za-z0-9_-]+)/, email.html_body) |> List.last()}
        )

        true
      end
    end)

    assert_received {:token, token}
    token
  end

  test "a request changes nothing until the new address confirms", %{identity: identity} do
    assert {:ok, _} =
             Accounts.request_email_change(identity.id, "New@Example.com", valid_password())

    u = user(identity)
    assert u.email == "old@example.com"
    assert u.pending_email == "new@example.com"
    # Only the hash is stored.
    refute u.pending_email_token == nil

    token = token_from_email()
    refute u.pending_email_token == token

    # The current address is told about it.
    assert_email_sent(to: [{"mailmover", "old@example.com"}], subject: ~r/being changed/)
    assert {:ok, _} = Accounts.authenticate_user("old@example.com", valid_password())
  end

  test "confirming applies the change, login follows it, and the link is single-use",
       %{identity: identity} do
    {:ok, _} = Accounts.request_email_change(identity.id, "new@example.com", valid_password())
    token = token_from_email()

    assert {:ok, _} = Accounts.confirm_email_change(token)

    u = user(identity)
    assert u.email == "new@example.com"
    assert is_nil(u.pending_email) and is_nil(u.pending_email_token)
    assert {:ok, _} = Accounts.authenticate_user("new@example.com", valid_password())
    assert {:error, _} = Accounts.authenticate_user("old@example.com", valid_password())

    assert {:error, :invalid_token} = Accounts.confirm_email_change(token)
  end

  test "requires the account password", %{identity: identity} do
    assert {:error, :invalid_password} =
             Accounts.request_email_change(identity.id, "new@example.com", "wrong-password")

    assert is_nil(user(identity).pending_email)
  end

  test "rejects a taken address, the current one, and a malformed one", %{identity: identity} do
    create_user("someoneelse", "taken@example.com")

    assert {:error, :email_taken} =
             Accounts.request_email_change(identity.id, "TAKEN@example.com", valid_password())

    assert {:error, :same_email} =
             Accounts.request_email_change(identity.id, "old@example.com", valid_password())

    assert {:error, %Ecto.Changeset{}} =
             Accounts.request_email_change(identity.id, "not-an-email", valid_password())
  end

  test "an expired link does nothing", %{identity: identity} do
    {:ok, _} = Accounts.request_email_change(identity.id, "new@example.com", valid_password())
    token = token_from_email()

    user(identity)
    |> Ecto.Changeset.change(pending_email_sent_at: DateTime.add(DateTime.utc_now(), -2, :day))
    |> Repo.update!()

    assert {:error, :token_expired} = Accounts.confirm_email_change(token)
    assert user(identity).email == "old@example.com"
  end

  test "the address is re-checked at confirm time", %{identity: identity} do
    {:ok, _} = Accounts.request_email_change(identity.id, "new@example.com", valid_password())
    token = token_from_email()
    create_user("racer", "new@example.com")

    assert {:error, :email_taken} = Accounts.confirm_email_change(token)
    assert user(identity).email == "old@example.com"
  end

  test "cancelling drops the pending change and its link", %{identity: identity} do
    {:ok, _} = Accounts.request_email_change(identity.id, "new@example.com", valid_password())
    token = token_from_email()

    assert {:ok, _} = Accounts.cancel_email_change(identity.id)
    assert is_nil(user(identity).pending_email)
    assert {:error, :invalid_token} = Accounts.confirm_email_change(token)
  end

  test "the endpoints map outcomes to error codes", %{identity: identity} do
    conn = Phoenix.ConnTest.build_conn() |> auth_conn(identity)

    conn
    |> Phoenix.ConnTest.dispatch(
      HybridsocialWeb.Endpoint,
      :post,
      "/api/v1/accounts/change_email",
      %{
        "email" => "new@example.com",
        "password" => "wrong-password"
      }
    )
    |> Phoenix.ConnTest.json_response(403)

    resp =
      conn
      |> Phoenix.ConnTest.dispatch(
        HybridsocialWeb.Endpoint,
        :post,
        "/api/v1/accounts/change_email",
        %{
          "email" => "new@example.com",
          "password" => valid_password()
        }
      )
      |> Phoenix.ConnTest.json_response(200)

    assert resp["status"] == "pending"
    token = token_from_email()

    Phoenix.ConnTest.build_conn()
    |> Phoenix.ConnTest.dispatch(
      HybridsocialWeb.Endpoint,
      :post,
      "/api/v1/auth/confirm_email_change",
      %{
        "token" => token
      }
    )
    |> Phoenix.ConnTest.json_response(200)

    assert user(identity).email == "new@example.com"
  end
end
