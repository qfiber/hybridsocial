defmodule Hybridsocial.Federation.Validators.AnnounceValidator do
  @moduledoc "Validates Announce (boost) activities."

  alias Hybridsocial.Federation.Validators.CommonValidator

  def validate(%{"type" => "Announce", "object" => object} = activity)
      when is_binary(object) or is_map(object) do
    with :ok <- CommonValidator.validate(activity) do
      {:ok, activity}
    end
  end

  def validate(%{"type" => "Announce"}), do: {:error, "Announce must have an object"}
  def validate(_), do: {:error, "Not an Announce activity"}
end
