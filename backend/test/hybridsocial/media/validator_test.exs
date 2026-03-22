defmodule Hybridsocial.Media.ValidatorTest do
  use ExUnit.Case, async: true

  alias Hybridsocial.Media.Validator

  describe "validate_content_type/1" do
    test "detects JPEG" do
      data = <<0xFF, 0xD8, 0xFF, 0xE0, 0::size(160)>>
      assert {:ok, "image/jpeg"} = Validator.validate_content_type(data)
    end

    test "detects PNG" do
      data = <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0::size(80)>>
      assert {:ok, "image/png"} = Validator.validate_content_type(data)
    end

    test "detects GIF" do
      data = <<0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0::size(80)>>
      assert {:ok, "image/gif"} = Validator.validate_content_type(data)
    end

    test "detects WebP" do
      data =
        <<0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50, 0::size(80)>>

      assert {:ok, "image/webp"} = Validator.validate_content_type(data)
    end

    test "detects MP4" do
      data = <<0x00, 0x00, 0x00, 0x1C, 0x66, 0x74, 0x79, 0x70, 0::size(80)>>
      assert {:ok, "video/mp4"} = Validator.validate_content_type(data)
    end

    test "detects WebM" do
      data = <<0x1A, 0x45, 0xDF, 0xA3, 0::size(80)>>
      assert {:ok, "video/webm"} = Validator.validate_content_type(data)
    end

    test "rejects invalid data" do
      data = <<0x00, 0x00, 0x00, 0x00, 0::size(80)>>
      assert {:error, :invalid_content_type} = Validator.validate_content_type(data)
    end

    test "rejects empty binary" do
      assert {:error, :invalid_content_type} = Validator.validate_content_type(<<>>)
    end
  end

  describe "validate_file_size/2" do
    test "accepts files within image limit" do
      assert :ok = Validator.validate_file_size(5 * 1024 * 1024, "image/jpeg")
    end

    test "rejects files exceeding image limit" do
      assert {:error, :file_too_large} =
               Validator.validate_file_size(15 * 1024 * 1024, "image/jpeg")
    end

    test "accepts videos within limit" do
      assert :ok = Validator.validate_file_size(50 * 1024 * 1024, "video/mp4")
    end

    test "rejects videos exceeding limit" do
      assert {:error, :file_too_large} =
               Validator.validate_file_size(150 * 1024 * 1024, "video/mp4")
    end
  end

  describe "strip_metadata/1" do
    test "returns :ok (no-op)" do
      assert :ok = Validator.strip_metadata("/tmp/test.jpg")
    end
  end
end
