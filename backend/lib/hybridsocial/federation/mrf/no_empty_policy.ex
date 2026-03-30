defmodule Hybridsocial.Federation.MRF.NoEmptyPolicy do
  @moduledoc """
  Rejects Create activities with empty content and no attachments.
  """
  @behaviour Hybridsocial.Federation.MRF.Policy

  @impl true
  def filter(%{"type" => "Create", "object" => object} = activity) when is_map(object) do
    content = object["content"] || ""
    attachments = object["attachment"] || []

    has_content = String.trim(content) != ""
    has_attachments = is_list(attachments) and length(attachments) > 0
    has_poll = is_map(object["oneOf"]) or is_list(object["oneOf"]) or
               is_map(object["anyOf"]) or is_list(object["anyOf"])

    if has_content or has_attachments or has_poll do
      {:ok, activity}
    else
      {:reject, "Empty post: no content, attachments, or poll"}
    end
  end

  def filter(activity), do: {:ok, activity}

  @impl true
  def describe do
    {:ok, %{name: "no_empty", description: "Rejects posts with no content or attachments."}}
  end
end
