defmodule HybridsocialWeb.Api.V1.MediaController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Media

  @doc """
  POST /api/v1/media - Upload a media file.
  Accepts multipart with `file` field and optional `alt_text`.
  """
  def create(conn, %{"file" => %Plug.Upload{} = upload} = params) do
    identity = conn.assigns.current_identity
    identity_id = identity.id
    alt_text = params["alt_text"]
    limits = Hybridsocial.Premium.TierLimits.limits_for(identity)

    # Enforce tier-based file size limits
    file_size = File.stat!(upload.path).size
    content_type = upload.content_type || ""
    is_video = String.starts_with?(content_type, "video/")
    max_bytes = if is_video, do: (limits[:video_size_mb] || 40) * 1_048_576, else: (limits[:image_size_mb] || 10) * 1_048_576

    if file_size > max_bytes do
      max_mb = if is_video, do: limits[:video_size_mb] || 40, else: limits[:image_size_mb] || 10
      conn
      |> put_status(:request_entity_too_large)
      |> json(%{error: "media.file_too_large", max_mb: max_mb})
    else

    case Media.upload(identity_id, upload, alt_text) do
      {:ok, media} ->
        conn
        |> put_status(:created)
        |> json(render_media(media))

      {:error, :invalid_content_type} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "media.invalid_content_type"})

      {:error, :file_too_large} ->
        conn
        |> put_status(:request_entity_too_large)
        |> json(%{error: "media.file_too_large"})

      {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "media.upload_failed", details: format_errors(changeset)})

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "media.upload_failed"})
    end

    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "media.file_required"})
  end

  @doc """
  GET /api/v1/media/:id - Show a media record.
  """
  def show(conn, %{"id" => id}) do
    case Media.get_media(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "media.not_found"})

      media ->
        conn
        |> put_status(:ok)
        |> json(render_media(media))
    end
  end

  @doc """
  PUT /api/v1/media/:id - Update a media record (alt text only).
  """
  def update(conn, %{"id" => id} = params) do
    identity_id = conn.assigns.current_identity.id
    alt_text = params["alt_text"] || ""

    case Media.update_alt_text(id, identity_id, alt_text) do
      {:ok, media} ->
        conn
        |> put_status(:ok)
        |> json(render_media(media))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "media.not_found"})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "media.unauthorized"})

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "media.update_failed"})
    end
  end

  defp render_media(media) do
    %{
      id: media.id,
      content_type: media.content_type,
      file_size: media.file_size,
      alt_text: media.alt_text,
      blurhash: media.blurhash,
      width: media.width,
      height: media.height,
      duration: media.duration,
      processing_status: media.processing_status,
      url: Media.media_url(media),
      inserted_at: media.inserted_at
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
