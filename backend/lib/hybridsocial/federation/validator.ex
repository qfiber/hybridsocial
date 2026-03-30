defmodule Hybridsocial.Federation.Validator do
  @moduledoc """
  Dispatcher for ActivityPub activity validation.

  Routes each activity to the appropriate type-specific validator.
  """

  alias Hybridsocial.Federation.Validators.{
    CreateValidator,
    UpdateValidator,
    DeleteValidator,
    FollowValidator,
    UndoValidator,
    AnnounceValidator,
    LikeValidator,
    BlockValidator,
    FlagValidator,
    CommonValidator
  }

  @doc """
  Validates an activity by dispatching to the correct validator based on type.
  Returns {:ok, activity} or {:error, reason}.
  """
  def validate(%{"type" => "Create"} = activity), do: CreateValidator.validate(activity)
  def validate(%{"type" => "Update"} = activity), do: UpdateValidator.validate(activity)
  def validate(%{"type" => "Delete"} = activity), do: DeleteValidator.validate(activity)
  def validate(%{"type" => "Follow"} = activity), do: FollowValidator.validate(activity)
  def validate(%{"type" => "Undo"} = activity), do: UndoValidator.validate(activity)
  def validate(%{"type" => "Announce"} = activity), do: AnnounceValidator.validate(activity)
  def validate(%{"type" => "Like"} = activity), do: LikeValidator.validate(activity)
  def validate(%{"type" => "EmojiReact"} = activity), do: LikeValidator.validate(activity)
  def validate(%{"type" => "Block"} = activity), do: BlockValidator.validate(activity)
  def validate(%{"type" => "Flag"} = activity), do: FlagValidator.validate(activity)

  # Accept, Reject, Add, Remove, Move — validate common fields only
  def validate(%{"type" => type} = activity)
      when type in ["Accept", "Reject", "Add", "Remove", "Move"] do
    case CommonValidator.validate(activity) do
      :ok -> {:ok, activity}
      {:error, _} = error -> error
    end
  end

  def validate(%{"type" => _} = activity) do
    # Unknown type — pass through with common validation
    case CommonValidator.validate(activity) do
      :ok -> {:ok, activity}
      {:error, _} = error -> error
    end
  end

  def validate(_), do: {:error, "Activity must have a type field"}
end
