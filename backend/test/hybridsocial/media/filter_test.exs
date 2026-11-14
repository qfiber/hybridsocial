defmodule Hybridsocial.Media.FilterTest do
  use Hybridsocial.DataCase, async: false

  alias Hybridsocial.Config
  alias Hybridsocial.Media.Filter
  alias Hybridsocial.Media.Filters.{Anonymize, Dedupe, ExifStrip}

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Hybridsocial.Repo, {:shared, self()})
    start_supervised!(Config.Store)
    :ok
  end

  test "unset keeps the default pipeline" do
    assert Filter.configured_filters() == [ExifStrip, Dedupe]
  end

  # Stripping location/device metadata from photos must not be switchable off.
  test "metadata stripping always runs first, whatever the setting says" do
    :ok = Config.set("upload_filters", ["Anonymize"])
    assert Filter.configured_filters() == [ExifStrip, Anonymize]

    :ok = Config.set("upload_filters", ["ExifStrip", "Dedupe"])
    assert Filter.configured_filters() == [ExifStrip, Dedupe]
  end

  test "an empty list means no optional filters, not the default" do
    :ok = Config.set("upload_filters", [])
    assert Filter.configured_filters() == [ExifStrip]
  end

  test "unknown names are ignored" do
    :ok = Config.set("upload_filters", ["Elixir.File", "Dedupe"])
    assert Filter.configured_filters() == [ExifStrip, Dedupe]
  end
end
