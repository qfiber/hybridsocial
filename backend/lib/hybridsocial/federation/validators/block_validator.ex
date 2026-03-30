defmodule Hybridsocial.Federation.Validators.BlockValidator do
  @moduledoc "Validates Block activities."

  alias Hybridsocial.Federation.Validators.CommonValidator

  def validate(%{"type" => "Block", "object" => object} = activity)
      when is_binary(object) do
    with :ok <- CommonValidator.validate(activity) do
      {:ok, activity}
    end
  end

  def validate(%{"type" => "Block"}), do: {:error, "Block must have an object (target actor URI)"}
  def validate(_), do: {:error, "Not a Block activity"}
end
