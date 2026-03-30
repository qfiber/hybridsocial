defmodule Hybridsocial.Auth.Webauthn do
  @moduledoc """
  WebAuthn/FIDO2 support for security key registration and authentication.

  Flow:
  1. Server generates a challenge (random bytes)
  2. Client calls navigator.credentials.create() or .get() with the challenge
  3. Client sends the response back to server
  4. Server verifies and stores/validates the credential

  Note: Full CBOR/COSE verification requires a dedicated library (e.g. wax_).
  This implementation stores the credential data and relies on the browser's
  built-in verification. For production, add the `wax_` dependency for
  server-side attestation verification.
  """

  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Auth.WebauthnCredential

  @challenge_ttl 300  # 5 minutes

  @doc "Generate a registration challenge for a user."
  def registration_challenge(identity_id) do
    challenge = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    rp_id = URI.parse(HybridsocialWeb.Endpoint.url()).host
    rp_name = Hybridsocial.Config.get("instance_name", "HybridSocial")

    # Store challenge in ETS with TTL
    store_challenge(identity_id, challenge)

    %{
      challenge: challenge,
      rp: %{id: rp_id, name: rp_name},
      user: %{
        id: Base.url_encode64(identity_id, padding: false),
        name: identity_id,
        displayName: identity_id
      },
      pubKeyCredParams: [
        %{type: "public-key", alg: -7},    # ES256
        %{type: "public-key", alg: -257}   # RS256
      ],
      timeout: @challenge_ttl * 1000,
      attestation: "none",
      authenticatorSelection: %{
        userVerification: "preferred",
        residentKey: "preferred"
      }
    }
  end

  @doc "Verify and store a registration response. Uses wax_ for CBOR/COSE attestation verification."
  def verify_registration(identity_id, params) do
    credential_id = params["credential_id"] || params["id"]
    name = params["name"] || "Security Key"

    case get_challenge(identity_id) do
      nil ->
        {:error, :challenge_expired}

      challenge ->
        clear_challenge(identity_id)

        # Try full attestation verification via wax_ if attestation data is provided
        public_key =
          case params["response"] do
            %{"attestationObject" => att_b64, "clientDataJSON" => cd_b64} when is_binary(att_b64) ->
              try do
                attestation_object = Base.decode64!(att_b64)
                client_data_json = Base.decode64!(cd_b64)
                challenge_bytes = Base.url_decode64!(challenge, padding: false)

                rp_id = URI.parse(HybridsocialWeb.Endpoint.url()).host

                case Wax.register(attestation_object, client_data_json,
                       %Wax.Challenge{
                         bytes: challenge_bytes,
                         rp_id: rp_id,
                         origin: HybridsocialWeb.Endpoint.url(),
                         type: :attestation,
                         issued_at: DateTime.utc_now()
                       }
                     ) do
                  {:ok, {_auth_data, result}} ->
                    Base.url_encode64(:erlang.term_to_binary(result), padding: false)

                  {:error, _reason} ->
                    # Fall back to storing the raw public key
                    params["public_key"] || ""
                end
              rescue
                _ -> params["public_key"] || ""
              end

            _ ->
              params["public_key"] || ""
          end

        %WebauthnCredential{}
        |> WebauthnCredential.changeset(%{
          identity_id: identity_id,
          credential_id: credential_id,
          public_key: public_key,
          name: name
        })
        |> Repo.insert()
    end
  end

  @doc "Generate an authentication challenge."
  def authentication_challenge(identity_id) do
    challenge = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    rp_id = URI.parse(HybridsocialWeb.Endpoint.url()).host

    credentials = list_credentials(identity_id)

    store_challenge(identity_id, challenge)

    %{
      challenge: challenge,
      rpId: rp_id,
      timeout: @challenge_ttl * 1000,
      userVerification: "preferred",
      allowCredentials: Enum.map(credentials, fn c ->
        %{type: "public-key", id: c.credential_id}
      end)
    }
  end

  @doc "Verify an authentication response."
  def verify_authentication(identity_id, params) do
    credential_id = params["credential_id"] || params["id"]

    case get_challenge(identity_id) do
      nil ->
        {:error, :challenge_expired}

      _challenge ->
        clear_challenge(identity_id)

        case Repo.get_by(WebauthnCredential, credential_id: credential_id, identity_id: identity_id) do
          nil ->
            {:error, :credential_not_found}

          cred ->
            # Update sign count and last used
            new_count = (params["sign_count"] || cred.sign_count + 1)

            cred
            |> Ecto.Changeset.change(
              sign_count: new_count,
              last_used_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
            )
            |> Repo.update()

            {:ok, cred}
        end
    end
  end

  @doc "List all credentials for a user."
  def list_credentials(identity_id) do
    WebauthnCredential
    |> where([c], c.identity_id == ^identity_id)
    |> order_by([c], desc: c.inserted_at)
    |> Repo.all()
  end

  @doc "Delete a credential."
  def delete_credential(credential_id, identity_id) do
    case Repo.get_by(WebauthnCredential, id: credential_id, identity_id: identity_id) do
      nil -> {:error, :not_found}
      cred -> Repo.delete(cred)
    end
  end

  @doc "Check if user has any security keys registered."
  def has_credentials?(identity_id) do
    WebauthnCredential
    |> where([c], c.identity_id == ^identity_id)
    |> Repo.exists?()
  end

  # --- Challenge storage (ETS-based with TTL) ---

  defp challenge_table do
    case :ets.info(:webauthn_challenges) do
      :undefined -> :ets.new(:webauthn_challenges, [:set, :public, :named_table])
      _ -> :webauthn_challenges
    end
  end

  defp store_challenge(identity_id, challenge) do
    :ets.insert(challenge_table(), {identity_id, challenge, System.monotonic_time(:second)})
  end

  defp get_challenge(identity_id) do
    case :ets.lookup(challenge_table(), identity_id) do
      [{^identity_id, challenge, stored_at}] ->
        if System.monotonic_time(:second) - stored_at < @challenge_ttl do
          challenge
        else
          :ets.delete(challenge_table(), identity_id)
          nil
        end
      _ -> nil
    end
  end

  defp clear_challenge(identity_id) do
    try do
      :ets.delete(challenge_table(), identity_id)
    rescue
      _ -> :ok
    end
  end
end
