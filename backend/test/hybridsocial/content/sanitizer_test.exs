defmodule Hybridsocial.Content.SanitizerTest do
  use ExUnit.Case, async: true

  alias Hybridsocial.Content.Sanitizer

  describe "markdown_to_html/1" do
    test "converts bold" do
      assert Sanitizer.markdown_to_html("**bold**") =~ "<strong>bold</strong>"
    end

    test "converts italic" do
      assert Sanitizer.markdown_to_html("*italic*") =~ "<em>italic</em>"
    end

    test "converts inline code" do
      assert Sanitizer.markdown_to_html("`code`") =~ "<code>code</code>"
    end

    test "converts paragraphs" do
      result = Sanitizer.markdown_to_html("para1\n\npara2")
      assert result =~ "<p>para1</p>"
      assert result =~ "<p>para2</p>"
    end

    test "converts line breaks" do
      result = Sanitizer.markdown_to_html("line1\nline2")
      assert result =~ "line1<br>line2"
    end

    test "converts hashtags to links" do
      result = Sanitizer.markdown_to_html("hello #elixir world")
      assert result =~ ~s(class="hashtag")
      assert result =~ "/tags/elixir"
    end

    test "escapes HTML" do
      result = Sanitizer.markdown_to_html("<script>alert('xss')</script>")
      refute result =~ "<script>"
      assert result =~ "&lt;script&gt;"
    end
  end

  describe "sanitize_html/1" do
    test "allows safe tags" do
      html = "<p>hello <strong>world</strong></p>"
      assert Sanitizer.sanitize_html(html) == html
    end

    test "strips dangerous tags" do
      html = "<p>hello</p><script>evil</script>"
      result = Sanitizer.sanitize_html(html)
      assert result =~ "<p>hello</p>"
      refute result =~ "<script>"
    end
  end

  describe "sanitize_links/1" do
    test "adds safety attributes to links" do
      html = ~s(<a href="https://example.com">link</a>)
      result = Sanitizer.sanitize_links(html)
      assert result =~ ~s(rel="nofollow noopener noreferrer")
      assert result =~ ~s(target="_blank")
    end

    test "strips non-http links" do
      html = "<a href=\"javascript:void\">link</a>"
      result = Sanitizer.sanitize_links(html)
      assert result =~ "href=\"#\""
    end
  end

  describe "sanitize_post_content/1" do
    test "returns nil for nil" do
      assert Sanitizer.sanitize_post_content(nil) == nil
    end

    test "full pipeline works" do
      result = Sanitizer.sanitize_post_content("**hello** #world")
      assert result =~ "<strong>hello</strong>"
      assert result =~ "#world"
    end
  end
end
