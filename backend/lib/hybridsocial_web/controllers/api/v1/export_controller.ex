defmodule HybridsocialWeb.Api.V1.ExportController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Portability

  # POST /api/v1/export
  def create(conn, _params) do
    identity = conn.assigns.current_identity

    case Portability.request_export(identity.id) do
      {:ok, export} ->
        # Generate the export (async in prod, sync in test)
        if Application.get_env(:hybridsocial, :env) == :test do
          Portability.generate_export(export.id)
        else
          Task.start(fn -> Portability.generate_export(export.id) end)
        end

        conn |> put_status(:accepted) |> json(serialize_export(export))

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # GET /api/v1/export
  def index(conn, _params) do
    identity = conn.assigns.current_identity
    exports = Portability.get_exports(identity.id)

    conn |> put_status(:ok) |> json(%{exports: Enum.map(exports, &serialize_export/1)})
  end

  # GET /api/v1/export/:id
  def show(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Portability.get_export(id, identity.id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "export.not_found"})

      export ->
        conn |> put_status(:ok) |> json(serialize_export(export))
    end
  end

  # GET /api/v1/export/:id/download
  def download(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Portability.get_export(id, identity.id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "export.not_found"})

      %{status: "completed", file_path: path} = export when is_binary(path) ->
        if File.exists?(path) do
          # Send the file, then delete it after download
          conn =
            conn
            |> put_resp_content_type("application/gzip")
            |> put_resp_header("content-disposition", "attachment; filename=\"hybridsocial-export.tar.gz\"")
            |> send_file(200, path)

          # Clean up: delete file and mark export as downloaded
          Task.start(fn ->
            File.rm(path)
            export
            |> Ecto.Changeset.change(file_path: nil)
            |> Hybridsocial.Repo.update()
          end)

          conn
        else
          conn |> put_status(:gone) |> json(%{error: "export.file_deleted"})
        end

      %{status: status} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "export.not_ready", status: status})
    end
  end

  # POST /api/v1/import
  def import_data(conn, %{"type" => type, "data" => data}) do
    identity = conn.assigns.current_identity

    result =
      case type do
        "follows" -> Portability.import_follows(identity.id, data)
        "blocks" -> Portability.import_blocks(identity.id, data)
        _ -> {:error, :invalid_type}
      end

    case result do
      {:ok, stats} ->
        conn |> put_status(:ok) |> json(stats)

      {:error, :invalid_type} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "import.invalid_type", message: "Supported types: follows, blocks"})
    end
  end

  def import_data(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "import.missing_params", message: "type and data are required"})
  end

  # DELETE /api/v1/accounts/delete (account deletion via portability)
  def request_deletion(conn, params) do
    identity = conn.assigns.current_identity
    reason = params["reason"]

    case Portability.request_deletion(identity.id, reason) do
      {:ok, deletion} ->
        conn
        |> put_status(:accepted)
        |> json(%{
          message: "account.deletion_scheduled",
          scheduled_for: deletion.scheduled_for
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  defp serialize_export(export) do
    %{
      id: export.id,
      status: export.status,
      file_size: export.file_size,
      requested_at: export.requested_at,
      completed_at: export.completed_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
