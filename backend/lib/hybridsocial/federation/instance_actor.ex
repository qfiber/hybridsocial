defmodule Hybridsocial.Federation.InstanceActor do
  @moduledoc """
  The instance-level ActivityPub actor.

  Used for:
  - Relay activities (Follow/Accept with relay servers)
  - Instance-level HTTP Signatures
  - Instance-to-instance communication

  Keys are loaded from environment variables (INSTANCE_PUBLIC_KEY / INSTANCE_PRIVATE_KEY)
  to keep them safe and portable across deployments.
  """

  @doc "Returns the instance actor's AP ID."
  def ap_id do
    "#{HybridsocialWeb.Endpoint.url()}/actor"
  end

  @doc "Returns the instance actor's inbox URL."
  def inbox_url do
    "#{HybridsocialWeb.Endpoint.url()}/inbox"
  end

  @doc "Returns the instance actor's public key PEM."
  def public_key do
    Application.get_env(:hybridsocial, :instance_public_key) ||
      raise "INSTANCE_PUBLIC_KEY not configured. Generate keys and set in environment."
  end

  @doc "Returns the instance actor's private key PEM."
  def private_key do
    Application.get_env(:hybridsocial, :instance_private_key) ||
      raise "INSTANCE_PRIVATE_KEY not configured. Generate keys and set in environment."
  end

  @doc "Returns true if instance keys are configured."
  def keys_configured? do
    Application.get_env(:hybridsocial, :instance_public_key) != nil &&
      Application.get_env(:hybridsocial, :instance_private_key) != nil
  end

  @doc """
  Serializes the instance actor as an ActivityPub Application actor.
  Served at /actor for remote instances to discover.
  """
  def to_ap do
    base_url = HybridsocialWeb.Endpoint.url()
    instance_name = Hybridsocial.Config.get("instance_name", "HybridSocial")

    %{
      "@context" => [
        "https://www.w3.org/ns/activitystreams",
        "https://w3id.org/security/v1"
      ],
      "id" => ap_id(),
      "type" => "Application",
      "preferredUsername" => "#{URI.parse(base_url).host}",
      "name" => instance_name,
      "summary" => Hybridsocial.Config.get("instance_description", ""),
      "url" => base_url,
      "inbox" => inbox_url(),
      "outbox" => "#{base_url}/actor/outbox",
      "publicKey" => %{
        "id" => "#{ap_id()}#main-key",
        "owner" => ap_id(),
        "publicKeyPem" => public_key()
      },
      "endpoints" => %{
        "sharedInbox" => inbox_url()
      }
    }
  end

  @doc """
  Generate an RSA keypair and print to stdout for copying into .env file.
  Run with: mix run -e "Hybridsocial.Federation.InstanceActor.generate_keys_to_stdout()"
  """
  def generate_keys_to_stdout do
    {public_pem, private_pem} = generate_rsa_keypair()

    IO.puts("# Add these to your .env file:")
    IO.puts("# The keys are base64-encoded to avoid multiline env var issues.")
    IO.puts("")
    IO.puts("INSTANCE_PUBLIC_KEY=#{Base.encode64(public_pem)}")
    IO.puts("")
    IO.puts("INSTANCE_PRIVATE_KEY=#{Base.encode64(private_pem)}")
  end

  @doc "Generate an RSA keypair, returns {public_pem, private_pem}."
  def generate_rsa_keypair do
    private_key = :public_key.generate_key({:rsa, 2048, 65537})
    private_entry = :public_key.pem_entry_encode(:RSAPrivateKey, private_key)
    private_pem = :public_key.pem_encode([private_entry])

    rsa_public = {:RSAPublicKey, elem(private_key, 2), elem(private_key, 3)}
    public_entry = :public_key.pem_entry_encode(:SubjectPublicKeyInfo, rsa_public)
    public_pem = :public_key.pem_encode([public_entry])

    {public_pem, private_pem}
  end
end
