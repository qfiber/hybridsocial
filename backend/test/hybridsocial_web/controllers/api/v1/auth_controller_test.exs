defmodule HybridsocialWeb.Api.V1.AuthControllerTest do
  use HybridsocialWeb.ConnCase, async: true

  alias Hybridsocial.Accounts

  @valid_attrs %{
    "handle" => "testuser",
    "display_name" => "Test User",
    "email" => "test@example.com",
    "password" => "password1234567890",
    "password_confirmation" => "password1234567890"
  }

  describe "POST /api/v1/auth/register" do
    test "creates account with valid data", %{conn: conn} do
      conn = post(conn, "/api/v1/auth/register", @valid_attrs)
      response = json_response(conn, 201)

      assert response["handle"] == "testuser"
      assert response["id"] != nil
      assert response["message"] == "account.confirmation_required"
    end

    test "returns errors with invalid data", %{conn: conn} do
      conn = post(conn, "/api/v1/auth/register", %{})
      response = json_response(conn, 422)

      assert response["error"] == "validation.failed"
    end

    test "rejects duplicate handle", %{conn: conn} do
      post(conn, "/api/v1/auth/register", @valid_attrs)
      conn = post(conn, "/api/v1/auth/register", %{@valid_attrs | "email" => "other@test.com"})
      response = json_response(conn, 422)

      assert response["error"] == "validation.failed"
    end
  end

  describe "POST /api/v1/auth/login" do
    setup %{conn: conn} do
      {:ok, identity} = Accounts.register_user(@valid_attrs)
      # register_user leaves the email unconfirmed; login 403s on an
      # unconfirmed email (email confirmation defaults on). Confirm it,
      # matching a real actor who has clicked the confirmation link.
      confirm_email(identity)
      %{conn: conn}
    end

    test "returns tokens with valid credentials", %{conn: conn} do
      conn =
        post(conn, "/api/v1/auth/login", %{
          "email" => "test@example.com",
          "password" => "password1234567890"
        })

      response = json_response(conn, 200)

      assert response["access_token"] != nil
      assert response["refresh_token"] != nil
      assert response["token_type"] == "Bearer"
      # Access-token TTL is Token.access_token_ttl() (7 days = 604800s).
      assert response["expires_in"] == Hybridsocial.Auth.Token.access_token_ttl()
    end

    test "rejects invalid password", %{conn: conn} do
      conn =
        post(conn, "/api/v1/auth/login", %{
          "email" => "test@example.com",
          "password" => "wrongpassword"
        })

      assert json_response(conn, 401)["error"] == "auth.invalid_credentials"
    end
  end

  describe "POST /api/v1/auth/refresh" do
    test "issues new tokens with valid refresh token", %{conn: conn} do
      {:ok, identity} = Accounts.register_user(@valid_attrs)
      # register_user leaves the email unconfirmed; login 403s on an
      # unconfirmed email (email confirmation defaults on). Confirm it,
      # matching a real actor who has clicked the confirmation link.
      confirm_email(identity)

      login_conn =
        post(conn, "/api/v1/auth/login", %{
          "email" => "test@example.com",
          "password" => "password1234567890"
        })

      %{"refresh_token" => refresh_token} = json_response(login_conn, 200)

      conn = post(conn, "/api/v1/auth/refresh", %{"refresh_token" => refresh_token})
      response = json_response(conn, 200)

      assert response["access_token"] != nil
      assert response["refresh_token"] != nil
      assert response["refresh_token"] != refresh_token
    end
  end

  describe "GET /api/v1/auth/me" do
    test "returns current user when authenticated", %{conn: conn} do
      {:ok, identity} = Accounts.register_user(@valid_attrs)
      # register_user leaves the email unconfirmed; login 403s on an
      # unconfirmed email (email confirmation defaults on). Confirm it,
      # matching a real actor who has clicked the confirmation link.
      confirm_email(identity)

      login_conn =
        post(conn, "/api/v1/auth/login", %{
          "email" => "test@example.com",
          "password" => "password1234567890"
        })

      %{"access_token" => token} = json_response(login_conn, 200)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/auth/me")

      response = json_response(conn, 200)
      assert response["handle"] == "testuser"
      assert response["email"] == "test@example.com"
    end

    # The privacy page reads these back; when they were missing, saving it
    # reset the invite settings to "anyone".
    test "returns the owner's own privacy settings", %{conn: conn} do
      identity = create_user("privacyowner")

      {:ok, identity} =
        identity
        |> Ecto.Changeset.change(
          allow_group_invites: "nobody",
          allow_page_invites: "only_follows",
          discoverable: false,
          also_known_as: ["https://old.example/users/me"]
        )
        |> Hybridsocial.Repo.update()

      response =
        conn
        |> auth_conn(identity)
        |> get("/api/v1/auth/me")
        |> json_response(200)

      assert response["allow_group_invites"] == "nobody"
      assert response["allow_page_invites"] == "only_follows"
      assert response["discoverable"] == false
      assert response["also_known_as"] == ["https://old.example/users/me"]
    end

    test "returns 401 without token", %{conn: conn} do
      conn = get(conn, "/api/v1/auth/me")
      assert json_response(conn, 401)["error"] == "auth.unauthorized"
    end
  end

  describe "POST /api/v1/auth/logout" do
    test "revokes token", %{conn: conn} do
      {:ok, identity} = Accounts.register_user(@valid_attrs)
      # register_user leaves the email unconfirmed; login 403s on an
      # unconfirmed email (email confirmation defaults on). Confirm it,
      # matching a real actor who has clicked the confirmation link.
      confirm_email(identity)

      login_conn =
        post(conn, "/api/v1/auth/login", %{
          "email" => "test@example.com",
          "password" => "password1234567890"
        })

      %{"access_token" => token} = json_response(login_conn, 200)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/auth/logout")

      assert json_response(conn, 200)["message"] == "auth.logged_out"

      # The access token must stop working immediately after logout — the
      # auth plug enforces revocation on top of the (still-unexpired) JWT.
      me_conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/auth/me")

      assert json_response(me_conn, 401)["error"] == "auth.unauthorized"
    end
  end

  describe "2FA setup flow" do
    setup %{conn: conn} do
      {:ok, identity} = Accounts.register_user(@valid_attrs)
      # register_user leaves the email unconfirmed; login 403s on an
      # unconfirmed email (email confirmation defaults on). Confirm it,
      # matching a real actor who has clicked the confirmation link.
      confirm_email(identity)

      login_conn =
        post(conn, "/api/v1/auth/login", %{
          "email" => "test@example.com",
          "password" => "password1234567890"
        })

      %{"access_token" => token, "identity_id" => identity_id} = json_response(login_conn, 200)

      authed_conn = put_req_header(conn, "authorization", "Bearer #{token}")
      %{conn: conn, authed_conn: authed_conn, identity_id: identity_id}
    end

    test "POST /api/v1/auth/2fa/setup returns secret and URI", %{authed_conn: conn} do
      conn = post(conn, "/api/v1/auth/2fa/setup")
      response = json_response(conn, 200)

      assert response["secret"] != nil
      assert response["uri"] != nil
      assert response["uri"] =~ "otpauth://totp/"
    end

    test "POST /api/v1/auth/2fa/verify enables 2FA with valid code", %{
      authed_conn: conn,
      identity_id: identity_id
    } do
      # Setup first
      setup_conn = post(conn, "/api/v1/auth/2fa/setup")
      %{"secret" => encoded_secret} = json_response(setup_conn, 200)
      {:ok, secret} = Base.decode32(encoded_secret, padding: false)

      # Generate a valid TOTP code
      code = NimbleTOTP.verification_code(secret)

      verify_conn = post(conn, "/api/v1/auth/2fa/verify", %{"code" => code})
      assert json_response(verify_conn, 200)["message"] == "2fa.enabled"

      # Confirm user has otp_enabled
      user = Hybridsocial.Repo.get!(Hybridsocial.Accounts.User, identity_id)
      assert user.otp_enabled == true
    end

    test "POST /api/v1/auth/2fa/verify rejects invalid code", %{authed_conn: conn} do
      # Setup first
      post(conn, "/api/v1/auth/2fa/setup")

      verify_conn = post(conn, "/api/v1/auth/2fa/verify", %{"code" => "000000"})
      assert json_response(verify_conn, 422)["error"] == "2fa.invalid_code"
    end
  end

  describe "2FA login flow" do
    setup %{conn: conn} do
      {:ok, identity} = Accounts.register_user(@valid_attrs)
      # register_user leaves the email unconfirmed; login 403s on an
      # unconfirmed email (email confirmation defaults on). Confirm it,
      # matching a real actor who has clicked the confirmation link.
      confirm_email(identity)

      # Login, setup, and enable 2FA
      login_conn =
        post(conn, "/api/v1/auth/login", %{
          "email" => "test@example.com",
          "password" => "password1234567890"
        })

      %{"access_token" => token, "identity_id" => identity_id} = json_response(login_conn, 200)

      authed_conn = put_req_header(conn, "authorization", "Bearer #{token}")

      setup_conn = post(authed_conn, "/api/v1/auth/2fa/setup")
      %{"secret" => encoded_secret} = json_response(setup_conn, 200)
      {:ok, secret} = Base.decode32(encoded_secret, padding: false)

      code = NimbleTOTP.verification_code(secret)
      post(authed_conn, "/api/v1/auth/2fa/verify", %{"code" => code})

      %{conn: conn, identity_id: identity_id, secret: secret, authed_conn: authed_conn}
    end

    test "login returns otp_required when 2FA is enabled", %{conn: conn} do
      conn =
        post(conn, "/api/v1/auth/login", %{
          "email" => "test@example.com",
          "password" => "password1234567890"
        })

      response = json_response(conn, 200)
      assert response["otp_required"] == true
      assert response["identity_id"] != nil
    end

    test "POST /api/v1/auth/2fa/login with valid code returns tokens", %{
      conn: conn,
      identity_id: identity_id,
      secret: secret
    } do
      code = NimbleTOTP.verification_code(secret)

      conn =
        post(conn, "/api/v1/auth/2fa/login", %{
          "identity_id" => identity_id,
          "code" => code
        })

      response = json_response(conn, 200)
      assert response["access_token"] != nil
      assert response["refresh_token"] != nil
    end

    test "POST /api/v1/auth/2fa/login with invalid code returns error", %{
      conn: conn,
      identity_id: identity_id
    } do
      conn =
        post(conn, "/api/v1/auth/2fa/login", %{
          "identity_id" => identity_id,
          "code" => "000000"
        })

      assert json_response(conn, 401)["error"] == "2fa.invalid_code"
    end
  end

  describe "DELETE /api/v1/auth/2fa" do
    setup %{conn: conn} do
      {:ok, identity} = Accounts.register_user(@valid_attrs)
      # register_user leaves the email unconfirmed; login 403s on an
      # unconfirmed email (email confirmation defaults on). Confirm it,
      # matching a real actor who has clicked the confirmation link.
      confirm_email(identity)

      login_conn =
        post(conn, "/api/v1/auth/login", %{
          "email" => "test@example.com",
          "password" => "password1234567890"
        })

      %{"access_token" => token, "identity_id" => identity_id} = json_response(login_conn, 200)

      authed_conn = put_req_header(conn, "authorization", "Bearer #{token}")

      # Setup and enable 2FA
      setup_conn = post(authed_conn, "/api/v1/auth/2fa/setup")
      %{"secret" => encoded_secret} = json_response(setup_conn, 200)
      {:ok, secret} = Base.decode32(encoded_secret, padding: false)

      code = NimbleTOTP.verification_code(secret)
      post(authed_conn, "/api/v1/auth/2fa/verify", %{"code" => code})

      %{authed_conn: authed_conn, identity_id: identity_id, secret: secret}
    end

    test "disables 2FA with valid code", %{
      authed_conn: conn,
      identity_id: identity_id,
      secret: secret
    } do
      code = NimbleTOTP.verification_code(secret)

      conn = delete(conn, "/api/v1/auth/2fa", %{"code" => code})
      assert json_response(conn, 200)["message"] == "2fa.disabled"

      # Confirm user has otp_enabled = false
      user = Hybridsocial.Repo.get!(Hybridsocial.Accounts.User, identity_id)
      assert user.otp_enabled == false
      assert user.otp_secret == nil
    end

    test "rejects disable with invalid code", %{authed_conn: conn} do
      conn = delete(conn, "/api/v1/auth/2fa", %{"code" => "000000"})
      assert json_response(conn, 422)["error"] == "2fa.invalid_code"
    end
  end
end
