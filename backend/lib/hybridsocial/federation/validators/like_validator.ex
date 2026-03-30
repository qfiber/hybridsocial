defmodule Hybridsocial.Federation.Validators.LikeValidator do
  @moduledoc "Validates Like activities."

  alias Hybridsocial.Federation.Validators.CommonValidator

  def validate(%{"type" => "Like", "object" => object} = activity)
      when is_binary(object) do
    with :ok <- CommonValidator.validate(activity) do
      {:ok, activity}
    end
  end

  def validate(%{"type" => "Like"}), do: {:error, "Like must have an object URI"}
  def validate(_), do: {:error, "Not a Like activity"}
end
