defmodule Hybridsocial.Federation.Validators.FlagValidator do
  @moduledoc "Validates Flag (report) activities."

  alias Hybridsocial.Federation.Validators.CommonValidator

  def validate(%{"type" => "Flag", "object" => objects} = activity)
      when is_list(objects) or is_binary(objects) do
    with :ok <- CommonValidator.validate(activity) do
      {:ok, activity}
    end
  end

  def validate(%{"type" => "Flag"}), do: {:error, "Flag must have objects (reported items)"}
  def validate(_), do: {:error, "Not a Flag activity"}
end
