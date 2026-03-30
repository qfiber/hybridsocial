defmodule Hybridsocial.Federation.Validators.CommonValidator do
  @moduledoc "Shared validation helpers for ActivityPub activities."

  @doc "Validates that the actor field is a valid URI string."
  def validate_actor(%{"actor" => actor}) when is_binary(actor) do
    if valid_uri?(actor), do: :ok, else: {:error, "Invalid actor URI"}
  end

  def validate_actor(_), do: {:error, "Missing or invalid actor"}

  @doc "Validates that the id field is a valid URI string."
  def validate_id(%{"id" => id}) when is_binary(id) do
    if valid_uri?(id), do: :ok, else: {:error, "Invalid activity id URI"}
  end

  def validate_id(_), do: {:error, "Missing or invalid id"}

  @doc "Validates that to/cc fields are lists of valid URIs."
  def validate_recipients(activity) do
    to = activity["to"]
    cc = activity["cc"]

    cond do
      not is_nil(to) and not is_list(to) ->
        {:error, "to field must be a list"}

      not is_nil(cc) and not is_list(cc) ->
        {:error, "cc field must be a list"}

      true ->
        :ok
    end
  end

  @doc "Runs all common validations on an activity."
  def validate(activity) do
    with :ok <- validate_id(activity),
         :ok <- validate_actor(activity),
         :ok <- validate_recipients(activity) do
      :ok
    end
  end

  defp valid_uri?(string) when is_binary(string) do
    case URI.parse(string) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        true

      _ ->
        false
    end
  end

  defp valid_uri?(_), do: false
end
