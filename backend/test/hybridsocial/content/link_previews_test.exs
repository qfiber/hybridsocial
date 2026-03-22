defmodule Hybridsocial.Content.LinkPreviewsTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Content.LinkPreviews

  describe "extract_urls/1" do
    test "extracts URLs from text" do
      text = "Check out https://example.com and http://test.org/page"
      urls = LinkPreviews.extract_urls(text)
      assert length(urls) == 2
      assert "https://example.com" in urls
      assert "http://test.org/page" in urls
    end

    test "returns empty list for text without URLs" do
      assert LinkPreviews.extract_urls("no urls here") == []
    end

    test "returns empty list for nil" do
      assert LinkPreviews.extract_urls(nil) == []
    end

    test "extracts URLs with paths and query strings" do
      text = "Visit https://example.com/path?q=1&b=2 for info"
      urls = LinkPreviews.extract_urls(text)
      assert length(urls) == 1
      assert hd(urls) == "https://example.com/path?q=1&b=2"
    end
  end

  describe "validate_url/1 - SSRF prevention" do
    test "rejects private IP addresses" do
      assert {:error, :private_ip} = LinkPreviews.validate_url("http://192.168.1.1/page")
      assert {:error, :private_ip} = LinkPreviews.validate_url("http://10.0.0.1/page")
      assert {:error, :private_ip} = LinkPreviews.validate_url("http://127.0.0.1/page")
      assert {:error, :private_ip} = LinkPreviews.validate_url("http://localhost/page")
    end

    test "rejects 172.16-31.x range" do
      assert {:error, :private_ip} = LinkPreviews.validate_url("http://172.16.0.1/page")
      assert {:error, :private_ip} = LinkPreviews.validate_url("http://172.31.255.255/page")
    end

    test "allows public IP addresses" do
      assert {:ok, _} = LinkPreviews.validate_url("http://8.8.8.8/page")
    end

    test "rejects URLs without host" do
      assert {:error, :invalid_url} = LinkPreviews.validate_url("not-a-url")
    end
  end
end
