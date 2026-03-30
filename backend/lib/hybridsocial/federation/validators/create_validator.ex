defmodule Hybridsocial.Federation.Validators.CreateValidator do
  @moduledoc "Validates Create activities."

  alias Hybridsocial.Federation.Validators.CommonValidator

  @doc "Validates a Create activity."
  def validate(%{"type" => "Create", "object" => object} = activity) when is_map(object) do
    with :ok <- CommonValidator.validate(activity),
         :ok <- validate_object_content(object),
         :ok <- validate_attributed_to(activity, object) do
      {:ok, activity}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def validate(%{"type" => "Create"}), do: {:error, "Create activity must have an embedded object"}
  def validate(_), do: {:error, "Not a Create activity"}

  defp validate_object_content(object) do
    content = object["content"]
    attachments = object["attachment"]

    has_content = is_binary(content) and String.trim(content) != ""
    has_attachments = is_list(attachments) and length(attachments) > 0

    if has_content or has_attachments do
      :ok
    else
      {:error, "Object must have content or attachments"}
    end
  end

  defp validate_attributed_to(activity, object) do
    actor = activity["actor"]
    attributed_to = object["attributedTo"]

    cond do
      is_nil(attributed_to) ->
        # attributedTo is optional in some implementations
        :ok

      is_binary(attributed_to) and attributed_to == actor ->
        :ok

      is_binary(attributed_to) ->
        {:error, "Actor does not match object attributedTo"}

      true ->
        :ok
    end
  end
end
