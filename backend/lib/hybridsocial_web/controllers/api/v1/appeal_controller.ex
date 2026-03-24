defmodule HybridsocialWeb.Api.V1.AppealController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Moderation

  # ── User-facing: submit and list own appeals ────────────────────────

  def create(conn, params) do
    identity_id = conn.assigns.current_identity.id

    attrs = %{
      "identity_id" => identity_id,
      "action_type" => params["action_type"],
      "reason" => params["reason"]
    }

    case Moderation.create_appeal(attrs) do
      {:ok, appeal} ->
        conn |> put_status(:created) |> json(%{data: serialize_appeal(appeal)})

      {:error, :already_pending} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "appeal.already_pending"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  def index(conn, params) do
    identity_id = conn.assigns.current_identity.id

    opts = [
      identity_id: identity_id,
      status: params["status"],
      limit: clamp_limit(params["limit"]),
      offset: parse_int(params["offset"], 0)
    ]

    appeals = Moderation.list_appeals(opts)

    conn
    |> put_status(:ok)
    |> json(%{data: Enum.map(appeals, &serialize_appeal/1)})
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  defp serialize_appeal(appeal) do
    %{
      id: appeal.id,
      identity_id: appeal.identity_id,
      action_type: appeal.action_type,
      reason: appeal.reason,
      status: appeal.status,
      reviewed_by: appeal.reviewed_by,
      reviewed_at: appeal.reviewed_at,
      response: appeal.response,
      created_at: appeal.inserted_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp clamp_limit(nil), do: 20
  defp clamp_limit(val) when is_binary(val), do: clamp_limit(parse_int(val, 20))
  defp clamp_limit(val) when is_integer(val), do: min(max(val, 1), 100)

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val
end
