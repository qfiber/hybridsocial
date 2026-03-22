defmodule Hybridsocial.Federation.ActivityMapperTest do
  use ExUnit.Case, async: true

  alias Hybridsocial.Federation.ActivityMapper

  describe "to_post/1" do
    test "converts a Note to post attributes" do
      ap_object = %{
        "id" => "https://remote.example/objects/note-1",
        "type" => "Note",
        "content" => "<p>Hello world!</p>",
        "attributedTo" => "https://remote.example/users/alice",
        "published" => "2026-03-22T12:00:00Z",
        "to" => ["https://www.w3.org/ns/activitystreams#Public"],
        "cc" => ["https://remote.example/users/alice/followers"],
        "sensitive" => false,
        "summary" => nil
      }

      result = ActivityMapper.to_post(ap_object)

      assert result["ap_id"] == "https://remote.example/objects/note-1"
      assert result["content"] == "<p>Hello world!</p>"
      assert result["content_html"] == "<p>Hello world!</p>"
      assert result["post_type"] == "text"
      assert result["visibility"] == "public"
      assert result["sensitive"] == false
    end

    test "converts an Article to post attributes with article type" do
      ap_object = %{
        "id" => "https://remote.example/objects/article-1",
        "type" => "Article",
        "content" => "<p>Long form content</p>",
        "attributedTo" => "https://remote.example/users/bob",
        "published" => "2026-03-22T12:00:00Z",
        "to" => ["https://www.w3.org/ns/activitystreams#Public"]
      }

      result = ActivityMapper.to_post(ap_object)
      assert result["post_type"] == "article"
    end

    test "handles content with sensitive flag and spoiler text" do
      ap_object = %{
        "id" => "https://remote.example/objects/sensitive-1",
        "type" => "Note",
        "content" => "Sensitive content",
        "sensitive" => true,
        "summary" => "Content warning",
        "to" => ["https://www.w3.org/ns/activitystreams#Public"]
      }

      result = ActivityMapper.to_post(ap_object)
      assert result["sensitive"] == true
      assert result["spoiler_text"] == "Content warning"
    end

    test "determines followers visibility when public is not in to/cc" do
      ap_object = %{
        "id" => "https://remote.example/objects/followers-1",
        "type" => "Note",
        "content" => "Followers only",
        "to" => ["https://remote.example/users/alice/followers"],
        "cc" => []
      }

      result = ActivityMapper.to_post(ap_object)
      assert result["visibility"] == "followers"
    end

    test "determines direct visibility when no public or followers address" do
      ap_object = %{
        "id" => "https://remote.example/objects/direct-1",
        "type" => "Note",
        "content" => "Direct message",
        "to" => ["https://remote.example/users/specific-user"],
        "cc" => []
      }

      result = ActivityMapper.to_post(ap_object)
      assert result["visibility"] == "direct"
    end

    test "parses inReplyTo as parent_ap_id" do
      ap_object = %{
        "id" => "https://remote.example/objects/reply-1",
        "type" => "Note",
        "content" => "A reply",
        "inReplyTo" => "https://remote.example/objects/parent-1",
        "to" => ["https://www.w3.org/ns/activitystreams#Public"]
      }

      result = ActivityMapper.to_post(ap_object)
      assert result["parent_ap_id"] == "https://remote.example/objects/parent-1"
    end

    test "extracts language from contentMap" do
      ap_object = %{
        "id" => "https://remote.example/objects/lang-1",
        "type" => "Note",
        "content" => "Bonjour",
        "contentMap" => %{"fr" => "Bonjour"},
        "to" => ["https://www.w3.org/ns/activitystreams#Public"]
      }

      result = ActivityMapper.to_post(ap_object)
      assert result["language"] == "fr"
    end

    test "parses published datetime" do
      ap_object = %{
        "id" => "https://remote.example/objects/time-1",
        "type" => "Note",
        "content" => "Timed post",
        "published" => "2026-03-22T15:30:00Z",
        "to" => ["https://www.w3.org/ns/activitystreams#Public"]
      }

      result = ActivityMapper.to_post(ap_object)
      assert %DateTime{} = result["published_at"]
      assert result["published_at"].year == 2026
      assert result["published_at"].month == 3
      assert result["published_at"].day == 22
    end
  end

  describe "to_actor/1" do
    test "converts an AP actor to remote_actor attributes" do
      ap_actor = %{
        "id" => "https://remote.example/users/alice",
        "type" => "Person",
        "preferredUsername" => "alice",
        "name" => "Alice Wonderland",
        "inbox" => "https://remote.example/users/alice/inbox",
        "outbox" => "https://remote.example/users/alice/outbox",
        "followers" => "https://remote.example/users/alice/followers",
        "icon" => %{"type" => "Image", "url" => "https://remote.example/avatars/alice.png"},
        "publicKey" => %{
          "id" => "https://remote.example/users/alice#main-key",
          "publicKeyPem" => "-----BEGIN PUBLIC KEY-----\ntest\n-----END PUBLIC KEY-----"
        },
        "endpoints" => %{
          "sharedInbox" => "https://remote.example/inbox"
        }
      }

      result = ActivityMapper.to_actor(ap_actor)

      assert result.ap_id == "https://remote.example/users/alice"
      assert result.handle == "alice"
      assert result.domain == "remote.example"
      assert result.display_name == "Alice Wonderland"
      assert result.inbox_url == "https://remote.example/users/alice/inbox"
      assert result.avatar_url == "https://remote.example/avatars/alice.png"
      assert result.public_key == "-----BEGIN PUBLIC KEY-----\ntest\n-----END PUBLIC KEY-----"
      assert result.shared_inbox_url == "https://remote.example/inbox"
    end

    test "handles actor without optional fields" do
      ap_actor = %{
        "id" => "https://remote.example/users/bob",
        "type" => "Person",
        "preferredUsername" => "bob",
        "inbox" => "https://remote.example/users/bob/inbox"
      }

      result = ActivityMapper.to_actor(ap_actor)
      assert result.ap_id == "https://remote.example/users/bob"
      assert result.handle == "bob"
      assert result.avatar_url == nil
      assert result.shared_inbox_url == nil
    end
  end

  describe "to_reaction_type/1" do
    test "maps heart emoji to love" do
      assert ActivityMapper.to_reaction_type("❤️") == "love"
      assert ActivityMapper.to_reaction_type("❤") == "love"
    end

    test "maps laughing emoji to lol" do
      assert ActivityMapper.to_reaction_type("😂") == "lol"
    end

    test "maps thumbs up to like" do
      assert ActivityMapper.to_reaction_type("👍") == "like"
    end

    test "maps sad emoji to sad" do
      assert ActivityMapper.to_reaction_type("😢") == "sad"
    end

    test "maps angry emoji to angry" do
      assert ActivityMapper.to_reaction_type("😡") == "angry"
    end

    test "maps care emoji to care" do
      assert ActivityMapper.to_reaction_type("🤗") == "care"
    end

    test "maps wtf emoji to wtf" do
      assert ActivityMapper.to_reaction_type("😱") == "wtf"
    end

    test "defaults to like for unknown emoji" do
      assert ActivityMapper.to_reaction_type("🍕") == "like"
    end

    test "defaults to like for nil" do
      assert ActivityMapper.to_reaction_type(nil) == "like"
    end

    test "defaults to like for empty string" do
      assert ActivityMapper.to_reaction_type("") == "like"
    end
  end

  describe "extract_domain/1" do
    test "extracts domain from URL" do
      assert ActivityMapper.extract_domain("https://mastodon.social/users/test") ==
               "mastodon.social"
    end

    test "returns nil for nil input" do
      assert ActivityMapper.extract_domain(nil) == nil
    end
  end
end
