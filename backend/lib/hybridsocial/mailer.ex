defmodule Hybridsocial.Mailer do
  use Swoosh.Mailer, otp_app: :hybridsocial

  import Swoosh.Email

  def send_test(to) do
    from_address = Hybridsocial.Config.get("email_from_address", "noreply@localhost")
    instance_name = Hybridsocial.Config.get("instance_name", "HybridSocial")

    email =
      new()
      |> to(to)
      |> from({instance_name, from_address})
      |> subject("Test email from #{instance_name}")
      |> text_body("This is a test email from #{instance_name}. If you received this, your email configuration is working correctly.")

    deliver(email)
  end
end
