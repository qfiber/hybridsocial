defmodule Hybridsocial.Media.AppIconsTest do
  use Hybridsocial.DataCase, async: false

  alias Hybridsocial.Config
  alias Hybridsocial.Media.AppIcons

  @favicon "https://media.example.com/favicon.svg"

  setup do
    # The config cache isn't in the test tree; start_supervised! tears it down
    # after each test, so settings can't leak between tests.
    start_supervised!(Hybridsocial.Config.Store)
    :ok
  end

  defp put_icons(source) do
    Config.set("app_icon_source", source)
    Config.set("app_icon_180_url", "https://media.example.com/180.png")
    Config.set("app_icon_192_url", "https://media.example.com/192.png")
    Config.set("app_icon_512_url", "https://media.example.com/512.png")
    Config.set("app_icon_maskable_url", "https://media.example.com/maskable.png")
  end

  describe "icons/0" do
    test "is nil with no favicon and no derived icons" do
      assert AppIcons.icons() == nil
    end

    test "returns the derived icons while their source is the current favicon" do
      Config.set("theme_favicon_url", @favicon)
      put_icons(@favicon)

      assert %{
               apple_touch: "https://media.example.com/180.png",
               icon_192: "https://media.example.com/192.png",
               icon_512: "https://media.example.com/512.png",
               maskable_512: "https://media.example.com/maskable.png"
             } = AppIcons.icons()
    end

    test "ignores icons derived from an older favicon" do
      # A new favicon too small to derive from leaves the old icon keys in
      # place; they must not keep showing the previous logo.
      put_icons("https://media.example.com/old.svg")
      Config.set("theme_favicon_url", @favicon)

      assert AppIcons.icons() == nil
    end

    test "is nil once the favicon is cleared" do
      put_icons(@favicon)
      Config.set("theme_favicon_url", "")

      assert AppIcons.icons() == nil
    end

    test "is nil when the set is incomplete" do
      Config.set("theme_favicon_url", @favicon)
      put_icons(@favicon)
      Config.set("app_icon_maskable_url", "")

      assert AppIcons.icons() == nil
    end
  end

  describe "derive" do
    test "rejects a non-upload input without raising" do
      assert {:error, :invalid_upload} = AppIcons.derive(nil, @favicon)
      assert {:error, :invalid_upload} = AppIcons.derive(%{not: :an_upload}, @favicon)
    end

    test "rejects a blank/invalid url without raising" do
      assert {:error, :invalid_url} = AppIcons.derive_from_url("")
      assert {:error, :invalid_url} = AppIcons.derive_from_url(nil)
    end
  end
end
