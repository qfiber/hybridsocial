defmodule Hybridsocial.Content.EmojisTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Content.Emojis

  describe "create_emoji/1" do
    test "creates an emoji with valid attributes" do
      assert {:ok, emoji} =
               Emojis.create_emoji(%{
                 "shortcode" => "thumbsup",
                 "image_url" => "https://example.com/thumbsup.png"
               })

      assert emoji.shortcode == "thumbsup"
      assert emoji.image_url == "https://example.com/thumbsup.png"
      assert emoji.enabled == true
    end

    test "creates an emoji with a category" do
      assert {:ok, emoji} =
               Emojis.create_emoji(%{
                 "shortcode" => "wave",
                 "image_url" => "https://example.com/wave.png",
                 "category" => "gestures"
               })

      assert emoji.category == "gestures"
    end

    test "fails without required fields" do
      assert {:error, changeset} = Emojis.create_emoji(%{})
      assert errors_on(changeset)[:shortcode] != nil
      assert errors_on(changeset)[:image_url] != nil
    end

    test "fails with duplicate shortcode" do
      Emojis.create_emoji(%{
        "shortcode" => "unique_emoji",
        "image_url" => "https://example.com/a.png"
      })

      assert {:error, changeset} =
               Emojis.create_emoji(%{
                 "shortcode" => "unique_emoji",
                 "image_url" => "https://example.com/b.png"
               })

      assert errors_on(changeset)[:shortcode] != nil
    end

    test "fails with invalid shortcode format" do
      assert {:error, changeset} =
               Emojis.create_emoji(%{
                 "shortcode" => "invalid emoji!",
                 "image_url" => "https://example.com/a.png"
               })

      assert errors_on(changeset)[:shortcode] != nil
    end
  end

  describe "list_emojis/1" do
    test "returns enabled emojis" do
      {:ok, _} =
        Emojis.create_emoji(%{
          "shortcode" => "smile",
          "image_url" => "https://example.com/smile.png"
        })

      {:ok, _} =
        Emojis.create_emoji(%{
          "shortcode" => "frown",
          "image_url" => "https://example.com/frown.png",
          "enabled" => false
        })

      emojis = Emojis.list_emojis()
      assert length(emojis) == 1
      assert hd(emojis).shortcode == "smile"
    end

    test "filters by category" do
      {:ok, _} =
        Emojis.create_emoji(%{
          "shortcode" => "cat",
          "image_url" => "https://example.com/cat.png",
          "category" => "animals"
        })

      {:ok, _} =
        Emojis.create_emoji(%{
          "shortcode" => "happy",
          "image_url" => "https://example.com/happy.png",
          "category" => "faces"
        })

      emojis = Emojis.list_emojis(category: "animals")
      assert length(emojis) == 1
      assert hd(emojis).shortcode == "cat"
    end
  end

  describe "get_emoji/1 and get_emoji_by_shortcode/1" do
    test "gets emoji by id" do
      {:ok, created} =
        Emojis.create_emoji(%{
          "shortcode" => "find_me",
          "image_url" => "https://example.com/find.png"
        })

      assert found = Emojis.get_emoji(created.id)
      assert found.shortcode == "find_me"
    end

    test "gets emoji by shortcode" do
      {:ok, _} =
        Emojis.create_emoji(%{
          "shortcode" => "lookup",
          "image_url" => "https://example.com/lookup.png"
        })

      assert found = Emojis.get_emoji_by_shortcode("lookup")
      assert found.image_url == "https://example.com/lookup.png"
    end

    test "returns nil for nonexistent emoji" do
      assert Emojis.get_emoji(Ecto.UUID.generate()) == nil
      assert Emojis.get_emoji_by_shortcode("nope") == nil
    end
  end

  describe "update_emoji/2" do
    test "updates an emoji" do
      {:ok, emoji} =
        Emojis.create_emoji(%{
          "shortcode" => "updatable",
          "image_url" => "https://example.com/old.png"
        })

      assert {:ok, updated} =
               Emojis.update_emoji(emoji.id, %{"image_url" => "https://example.com/new.png"})

      assert updated.image_url == "https://example.com/new.png"
    end

    test "returns error for nonexistent emoji" do
      assert {:error, :not_found} =
               Emojis.update_emoji(Ecto.UUID.generate(), %{
                 "image_url" => "https://example.com/x.png"
               })
    end
  end

  describe "delete_emoji/1" do
    test "deletes an emoji" do
      {:ok, emoji} =
        Emojis.create_emoji(%{
          "shortcode" => "deletable",
          "image_url" => "https://example.com/del.png"
        })

      assert {:ok, _} = Emojis.delete_emoji(emoji.id)
      assert Emojis.get_emoji(emoji.id) == nil
    end

    test "returns error for nonexistent emoji" do
      assert {:error, :not_found} = Emojis.delete_emoji(Ecto.UUID.generate())
    end
  end

  describe "render_emojis_in_text/1" do
    test "replaces shortcodes with image tags" do
      {:ok, _} =
        Emojis.create_emoji(%{
          "shortcode" => "fire",
          "image_url" => "https://example.com/fire.png"
        })

      result = Emojis.render_emojis_in_text("This is :fire:!")
      assert result =~ ~s(<img class="custom-emoji")
      assert result =~ ~s(src="https://example.com/fire.png")
      assert result =~ ~s(alt=":fire:")
    end

    test "leaves unknown shortcodes unchanged" do
      result = Emojis.render_emojis_in_text("This is :unknown_emoji:!")
      assert result == "This is :unknown_emoji:!"
    end

    test "handles nil input" do
      assert Emojis.render_emojis_in_text(nil) == nil
    end
  end
end
