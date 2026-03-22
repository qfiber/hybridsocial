defmodule Hybridsocial.Emails do
  @moduledoc """
  Email builder module. Constructs emails using Swoosh.Email.

  Uses templates from the Config system when available,
  falling back to built-in defaults.
  """

  import Swoosh.Email

  @default_from {"HybridSocial", "noreply@hybridsocial.local"}

  @doc """
  Builds an email confirmation email with a token link.
  """
  def confirmation_email(user) do
    instance_name = Hybridsocial.Config.get("instance_name", "HybridSocial")
    from_address = from_address()

    subject = "#{instance_name} - Confirm your email address"

    body = """
    Welcome to #{instance_name}!

    Please confirm your email address by clicking the link below:

    #{base_url()}/auth/confirm?token=#{user.confirmation_token}

    If you did not create an account, you can safely ignore this email.
    """

    new()
    |> to({user_display_name(user), user_email(user)})
    |> from(from_address)
    |> subject(subject)
    |> text_body(body)
  end

  @doc """
  Builds a password reset email with a token link.
  """
  def password_reset_email(user) do
    instance_name = Hybridsocial.Config.get("instance_name", "HybridSocial")
    from_address = from_address()

    subject = "#{instance_name} - Reset your password"

    body = """
    You requested a password reset for your #{instance_name} account.

    Click the link below to reset your password:

    #{base_url()}/auth/reset-password?token=#{user.reset_token}

    If you did not request this, you can safely ignore this email.
    This link will expire in 1 hour.
    """

    new()
    |> to({user_display_name(user), user_email(user)})
    |> from(from_address)
    |> subject(subject)
    |> text_body(body)
  end

  @doc """
  Builds a login notification email alerting the user of a new login.
  """
  def login_notification_email(user, ip, user_agent) do
    instance_name = Hybridsocial.Config.get("instance_name", "HybridSocial")
    from_address = from_address()

    subject = "#{instance_name} - New login to your account"

    body = """
    A new login was detected on your #{instance_name} account.

    IP Address: #{ip}
    Browser/App: #{user_agent}

    If this was you, no action is needed.
    If you did not log in, please change your password immediately.
    """

    new()
    |> to({user_display_name(user), user_email(user)})
    |> from(from_address)
    |> subject(subject)
    |> text_body(body)
  end

  @doc """
  Builds a notification digest email summarizing recent notifications.
  """
  def notification_digest_email(user, notifications) do
    instance_name = Hybridsocial.Config.get("instance_name", "HybridSocial")
    from_address = from_address()

    count = length(notifications)
    subject = "#{instance_name} - You have #{count} new notification#{if count != 1, do: "s"}"

    summary =
      notifications
      |> Enum.map(&format_notification/1)
      |> Enum.join("\n")

    body = """
    You have #{count} new notification#{if count != 1, do: "s"} on #{instance_name}:

    #{summary}

    Visit #{base_url()} to see all your notifications.
    """

    new()
    |> to({user_display_name(user), user_email(user)})
    |> from(from_address)
    |> subject(subject)
    |> text_body(body)
  end

  # Private helpers

  defp from_address do
    contact_email = Hybridsocial.Config.get("contact_email", "")
    instance_name = Hybridsocial.Config.get("instance_name", "HybridSocial")

    if contact_email != "" do
      {instance_name, contact_email}
    else
      @default_from
    end
  end

  defp base_url do
    endpoint_config = Application.get_env(:hybridsocial, HybridsocialWeb.Endpoint, [])
    url_config = Keyword.get(endpoint_config, :url, [])
    host = Keyword.get(url_config, :host, "localhost")
    scheme = Keyword.get(url_config, :scheme, "https")
    port = Keyword.get(url_config, :port, 443)

    case {scheme, port} do
      {"https", 443} -> "#{scheme}://#{host}"
      {"http", 80} -> "#{scheme}://#{host}"
      _ -> "#{scheme}://#{host}:#{port}"
    end
  end

  defp user_display_name(user) do
    cond do
      Map.has_key?(user, :display_name) and user.display_name ->
        user.display_name

      Map.has_key?(user, :handle) and user.handle ->
        user.handle

      true ->
        "User"
    end
  end

  defp user_email(user) do
    user.email
  end

  defp format_notification(notification) do
    type = notification[:type] || notification["type"] || "unknown"
    "- #{type} notification"
  end
end
