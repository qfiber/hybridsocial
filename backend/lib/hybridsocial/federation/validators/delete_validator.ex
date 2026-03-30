defmodule Hybridsocial.Federation.Validators.DeleteValidator do
  @moduledoc "Validates Delete activities. Actor must match the object author."

  alias Hybridsocial.Federation.Validators.CommonValidator
  alias Hybridsocial.Federation.Containment

  def validate(%{"type" => "Delete"} = activity) do
    with :ok <- CommonValidator.validate(activity),
         :ok <- validate_actor_owns_object(activity) do
      {:ok, activity}
    end
  end

  def validate(_), do: {:error, "Not a Delete activity"}

  defp validate_actor_owns_object(activity) do
    actor = activity["actor"]
    object = activity["object"]

    object_id =
      case object do
        id when is_binary(id) -> id
        %{"id" => id} when is_binary(id) -> id
        _ -> nil
      end

    cond do
      is_nil(object_id) ->
        {:error, "Delete must specify an object"}

      # Actor deleting themselves
      object_id == actor ->
        :ok

      # Object from same domain as actor
      Containment.same_origin(actor, object_id) == :ok ->
        :ok

      true ->
        {:error, "Actor cannot delete objects from another domain"}
    end
  end
end
