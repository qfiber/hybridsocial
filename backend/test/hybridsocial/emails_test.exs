defmodule Hybridsocial.EmailsTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Emails

  defp build_user(attrs \\ %{}) do
    Map.merge(
      %{
        email: "test@example.com",
        handle: "testuser",
        display_name: "Test User",
        confirmation_token: "confirm-token-123",
        reset_token: "reset-token-456"
      },
      attrs
    )
  end

  describe "confirmation_email/1" do
    test "builds a confirmation email" do
      user = build_user()
      email = Emails.confirmation_email(user)

      assert email.to == [{"Test User", "test@example.com"}]
      assert email.subject =~ "Confirm your email"
      assert email.text_body =~ "confirm-token-123"
      assert email.text_body =~ "confirm"
    end
  end

  describe "password_reset_email/1" do
    test "builds a password reset email" do
      user = build_user()
      email = Emails.password_reset_email(user)

      assert email.to == [{"Test User", "test@example.com"}]
      assert email.subject =~ "Reset your password"
      assert email.text_body =~ "reset-token-456"
    end
  end

  describe "login_notification_email/3" do
    test "builds a login notification email" do
      user = build_user()
      email = Emails.login_notification_email(user, "192.168.1.1", "Mozilla/5.0")

      assert email.to == [{"Test User", "test@example.com"}]
      assert email.subject =~ "New login"
      assert email.text_body =~ "192.168.1.1"
      assert email.text_body =~ "Mozilla/5.0"
    end
  end

  describe "notification_digest_email/2" do
    test "builds a notification digest email with multiple notifications" do
      user = build_user()

      notifications = [
        %{type: "follow", account: "user2"},
        %{type: "mention", account: "user3"}
      ]

      email = Emails.notification_digest_email(user, notifications)

      assert email.to == [{"Test User", "test@example.com"}]
      assert email.subject =~ "2 new notifications"
      assert email.text_body =~ "follow"
      assert email.text_body =~ "mention"
    end

    test "builds a notification digest email with a single notification" do
      user = build_user()
      notifications = [%{type: "follow", account: "user2"}]

      email = Emails.notification_digest_email(user, notifications)

      assert email.subject =~ "1 new notification"
      refute email.subject =~ "notifications"
    end
  end
end
