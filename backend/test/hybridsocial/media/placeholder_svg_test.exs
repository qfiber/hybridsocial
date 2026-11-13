defmodule Hybridsocial.Media.PlaceholderSvgTest do
  use ExUnit.Case, async: true

  alias Hybridsocial.Media.PlaceholderSvg

  defp parses?(svg) do
    # xmerl wants UTF-8 bytes, not codepoints (the SVGs have em dashes).
    {_doc, _rest} = svg |> :erlang.binary_to_list() |> :xmerl_scan.string(quiet: true)
    true
  catch
    _, _ -> false
  end

  test "unavailable is a well-formed, neutral image titled by media kind" do
    for {kind, title} <- [
          image: "Image not available",
          video: "Video not available",
          audio: "Audio not available"
        ] do
      svg = PlaceholderSvg.unavailable(kind)
      assert parses?(svg)
      assert svg =~ title
      # Slate palette, not the red danger one.
      assert svg =~ "#1e293b"
      refute svg =~ "#7f1d1d"
    end

    assert PlaceholderSvg.unavailable() =~ "Image not available"
  end

  test "the malware placeholders keep the danger palette and stay well-formed" do
    for svg <- [PlaceholderSvg.infected(), PlaceholderSvg.scanner_unreachable()] do
      assert parses?(svg)
      assert svg =~ "#7f1d1d"
    end
  end
end
