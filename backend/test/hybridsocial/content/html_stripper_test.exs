defmodule Hybridsocial.Content.HtmlStripperTest do
  use ExUnit.Case, async: true

  alias Hybridsocial.Content.HtmlStripper

  describe "decode_entities/1" do
    test "decodes the entities the sanitizer emits" do
      assert HtmlStripper.decode_entities("&quot;a&quot; &amp; &#39;b&#39; &lt;c&gt;") ==
               ~s("a" & 'b' <c>)
    end

    test "decodes an escaped entity only once" do
      # `&amp;quot;` is the literal text "&quot;", not a quote mark.
      assert HtmlStripper.decode_entities("&amp;quot;") == "&quot;"
    end
  end

  test "to_plaintext keeps line breaks and decodes entities" do
    assert HtmlStripper.to_plaintext("<p>a &amp; b</p><p>&quot;c&quot;<br>d</p>") ==
             ~s(a & b\n\n"c"\nd)
  end
end
