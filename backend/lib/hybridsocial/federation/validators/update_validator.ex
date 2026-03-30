defmodule Hybridsocial.Federation.Validators.UpdateValidator do
  @moduledoc "Validates Update activities."

  alias Hybridsocial.Federation.Validators.CommonValidator

  def validate(%{"type" => "Update", "object" => object} = activity) when is_map(object) do
    with :ok <- CommonValidator.validate(activity) do
      {:ok, activity}
    end
  end

  def validate(%{"type" => "Update"}), do: {:error, "Update activity must have an embedded object"}
  def validate(_), do: {:error, "Not an Update activity"}
end
