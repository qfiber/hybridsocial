defmodule Hybridsocial.Federation.Validators.UndoValidator do
  @moduledoc "Validates Undo activities."

  alias Hybridsocial.Federation.Validators.CommonValidator

  def validate(%{"type" => "Undo", "object" => object} = activity)
      when is_map(object) or is_binary(object) do
    with :ok <- CommonValidator.validate(activity) do
      {:ok, activity}
    end
  end

  def validate(%{"type" => "Undo"}), do: {:error, "Undo must have an object"}
  def validate(_), do: {:error, "Not an Undo activity"}
end
