defmodule HybridsocialWeb.Federation.InboxController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Federation
  alias Hybridsocial.Federation.{Inbox, ActivityMapper}

  require Logger

  @doc """
  Handles POST to /actors/:id/inbox (actor-specific inbox).
  """
  def actor_inbox(conn, %{"id" => _actor_id} = params) do
    process_inbox(conn, params)
  end

  @doc """
  Handles POST to /inbox (shared inbox).
  """
  def shared_inbox(conn, params) do
    process_inbox(conn, params)
  end

  defp process_inbox(conn, activity) do
    with :ok <- verify_http_signature(conn),
         :ok <- check_sender_policy(activity),
         :ok <- check_dedup(activity),
         {:ok, _result} <- Inbox.process(activity) do
      # Record the activity for dedup
      record_activity_dedup(activity)

      conn
      |> put_status(202)
      |> json(%{status: "accepted"})
    else
      {:error, :signature_invalid} ->
        conn
        |> put_status(401)
        |> json(%{error: "Invalid HTTP signature"})

      {:error, :domain_suspended} ->
        conn
        |> put_status(403)
        |> json(%{error: "Domain suspended"})

      {:error, :duplicate_activity} ->
        # Silently accept duplicates to be idempotent
        conn
        |> put_status(202)
        |> json(%{status: "accepted"})

      {:error, reason} ->
        Logger.warning("Inbox processing failed: #{inspect(reason)}")

        conn
        |> put_status(422)
        |> json(%{error: "Unprocessable activity", reason: to_string(reason)})
    end
  end

  # Verify HTTP signatures on incoming federation requests.
  defp verify_http_signature(conn) do
    if Application.get_env(:hybridsocial, :federation_signature_check, true) do
      case Hybridsocial.Federation.HTTPSignature.verify(conn) do
        {:ok, _key_id} -> :ok
        {:error, reason} ->
          Logger.warning("HTTP signature verification failed: #{inspect(reason)}")
          {:error, :signature_invalid}
      end
    else
      :ok
    end
  end

  # Check instance policy for the sender's domain using the Federation context.
  defp check_sender_policy(%{"actor" => actor_ap_id}) when is_binary(actor_ap_id) do
    domain = ActivityMapper.extract_domain(actor_ap_id)

    if domain do
      if Federation.domain_allowed?(domain) do
        :ok
      else
        {:error, :domain_suspended}
      end
    else
      {:error, :invalid_actor}
    end
  end

  defp check_sender_policy(_), do: {:error, :missing_actor}

  # Check for duplicate activities using the Federation dedup system.
  defp check_dedup(%{"id" => activity_id}) when is_binary(activity_id) do
    activity_hash = :crypto.hash(:sha256, activity_id) |> Base.encode16(case: :lower)

    if Federation.deduplicate?(activity_hash) do
      {:error, :duplicate_activity}
    else
      :ok
    end
  end

  defp check_dedup(_), do: :ok

  # Record a processed activity for future dedup checks.
  defp record_activity_dedup(%{"id" => activity_id}) when is_binary(activity_id) do
    activity_hash = :crypto.hash(:sha256, activity_id) |> Base.encode16(case: :lower)
    Federation.record_dedup(activity_hash, activity_id)
  end

  defp record_activity_dedup(_), do: :ok
end
