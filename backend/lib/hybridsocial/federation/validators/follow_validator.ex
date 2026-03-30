defmodule Hybridsocial.Federation.Validators.FollowValidator do
  @moduledoc "Validates Follow activities."

  alias Hybridsocial.Federation.Validators.CommonValidator

  def validate(%{"type" => "Follow", "object" => object} = activity)
      when is_binary(object) do
    with :ok <- CommonValidator.validate(activity) do
      {:ok, activity}
    end
  end

  def validate(%{"type" => "Follow"}), do: {:error, "Follow must have an object (target actor URI)"}
  def validate(_), do: {:error, "Not a Follow activity"}
end
