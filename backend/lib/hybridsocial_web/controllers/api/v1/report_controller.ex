defmodule HybridsocialWeb.Api.V1.ReportController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Moderation

  def create(conn, params) do
    reporter_id = conn.assigns.current_identity.id

    case Moderation.create_report(reporter_id, params) do
      {:ok, report} ->
        conn
        |> put_status(:created)
        |> json(%{
          id: report.id,
          category: report.category,
          status: report.status,
          message: "report.created"
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
