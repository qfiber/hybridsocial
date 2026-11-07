defmodule Hybridsocial.Federation.MRFIntegrationTest do
  @moduledoc """
  Integration tests for MRF policies, exercised via Inbox.process — not the
  policy modules directly.

  The unit tests in mrf_test.exs prove each policy works in isolation. These
  tests prove the full inbox pipeline actually reaches them when configured,
  catching the failure mode where a policy is correct but unreachable
  (e.g. validator gap, dispatch order, missing config wiring).
  """
  use Hybridsocial.DataCase, async: false

  alias Hybridsocial.Config
  alias Hybridsocial.Federation
  alias Hybridsocial.Federation.Inbox

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Hybridsocial.Repo, {:shared, self()})
    start_supervised!(Hybridsocial.Config.Store)
    :ok
  end

  # --------------------------------------------------------------------------
  # Fixtures
  # --------------------------------------------------------------------------

  defp create_activity(overrides \\ %{}) do
    base = %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "id" => "https://remote.example/activities/create-#{:erlang.unique_integer([:positive])}",
      "type" => "Create",
      "actor" => "https://remote.example/u/alice",
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "object" => %{
        "id" => "https://remote.example/objects/note-#{:erlang.unique_integer([:positive])}",
        "type" => "Note",
        "content" => "Hello world",
        "attributedTo" => "https://remote.example/u/alice",
        "published" => "2026-04-13T12:00:00Z",
        "to" => ["https://www.w3.org/ns/activitystreams#Public"]
      }
    }

    deep_merge(base, overrides)
  end

  defp deep_merge(left, right) do
    Map.merge(left, right, fn
      _, %{} = l, %{} = r -> deep_merge(l, r)
      _, _, r -> r
    end)
  end

  defp configure_policies(names) do
    :ok = Config.set("mrf_policies", names)
  end

  # --------------------------------------------------------------------------
  # SimplePolicy via Inbox
  # --------------------------------------------------------------------------

  describe "SimplePolicy via Inbox.process" do
    test "enforces a silence policy without any mrf_policies setting" do
      configure_policies([])
      {:ok, _} = Federation.set_instance_policy("remote.example", "silence", "loud", nil)

      assert {:ok, post} = Inbox.process(create_activity())
      assert post.visibility != "public"
    end

    test "rejects a Create from a suspended domain with mrf_rejected" do
      configure_policies(["simple"])
      {:ok, _} = Federation.set_instance_policy("remote.example", "suspend", "spam", nil)

      assert {:error, {:mrf_rejected, reason}} = Inbox.process(create_activity())
      assert reason =~ "remote.example"
    end

    test "lets a Create through when no domain policy applies" do
      configure_policies(["simple"])
      # Insert a policy for some OTHER domain so the table is non-empty
      {:ok, _} = Federation.set_instance_policy("other.example", "suspend", "x", nil)

      assert {:ok, _post} = Inbox.process(create_activity())
    end

    test "strips the public collection from a silenced domain's addressing" do
      configure_policies(["simple"])
      {:ok, _} = Federation.set_instance_policy("remote.example", "silence", "loud", nil)

      # Silenced domains aren't rejected — the post is created but with
      # public addressing stripped, so it federates as followers-only.
      assert {:ok, post} = Inbox.process(create_activity())
      assert post.visibility != "public"
    end
  end

  # --------------------------------------------------------------------------
  # Content filters via Inbox
  # --------------------------------------------------------------------------

  describe "content filters on remote posts" do
    alias Hybridsocial.Moderation
    alias Hybridsocial.Moderation.QueuedItem

    defp with_content(content), do: create_activity(%{"object" => %{"content" => content}})

    test "reject refuses the post" do
      {:ok, _} =
        Moderation.create_filter(%{
          "type" => "word",
          "pattern" => "spamword",
          "action" => "reject"
        })

      assert {:error, :content_rejected} = Inbox.process(with_content("buy spamword today"))
    end

    test "flag publishes the post and adds it to the review queue" do
      {:ok, _} =
        Moderation.create_filter(%{
          "type" => "phrase",
          "pattern" => "look at",
          "action" => "flag"
        })

      assert {:ok, post} = Inbox.process(with_content("please look at this"))
      assert Repo.get_by(QueuedItem, item_id: post.id, source: "content_filter")
    end

    test "a whole-word filter doesn't match inside a longer word" do
      {:ok, _} =
        Moderation.create_filter(%{"type" => "word", "pattern" => "ass", "action" => "reject"})

      assert {:ok, _} = Inbox.process(with_content("a classic example"))
    end
  end

  # --------------------------------------------------------------------------
  # HellthreadPolicy via Inbox
  # --------------------------------------------------------------------------

  describe "HellthreadPolicy via Inbox.process" do
    test "rejects a Create whose mention count exceeds the threshold" do
      configure_policies(["hellthread"])
      :ok = Config.set("mrf_hellthread_threshold", 5)

      recipients = for i <- 1..6, do: "https://remote.example/u/user#{i}"
      activity = create_activity(%{"to" => recipients})

      assert {:error, {:mrf_rejected, reason}} = Inbox.process(activity)
      assert reason =~ "Hellthread"
    end

    test "lets a Create through when mentions are at or below the threshold" do
      configure_policies(["hellthread"])
      :ok = Config.set("mrf_hellthread_threshold", 5)

      recipients = for i <- 1..5, do: "https://remote.example/u/user#{i}"
      activity = create_activity(%{"to" => recipients})

      assert {:ok, _} = Inbox.process(activity)
    end
  end

  # --------------------------------------------------------------------------
  # KeywordPolicy via Inbox
  # --------------------------------------------------------------------------

  describe "KeywordPolicy via Inbox.process" do
    test "rejects a Create whose object content matches a reject keyword" do
      configure_policies(["keyword"])
      :ok = Config.set("mrf_keyword_reject", ["forbidden"])

      activity = create_activity(%{"object" => %{"content" => "this is FORBIDDEN content"}})

      assert {:error, {:mrf_rejected, reason}} = Inbox.process(activity)
      assert reason =~ "Keyword"
    end

    test "rewrites content when a replace pattern is configured" do
      configure_policies(["keyword"])
      :ok = Config.set("mrf_keyword_reject", [])

      :ok =
        Config.set("mrf_keyword_replace", [%{"pattern" => "shout", "replacement" => "whisper"}])

      activity = create_activity(%{"object" => %{"content" => "shout louder"}})

      assert {:ok, post} = Inbox.process(activity)
      assert post.content =~ "whisper"
      refute post.content =~ "shout"
    end
  end

  # --------------------------------------------------------------------------
  # Pipeline composition
  # --------------------------------------------------------------------------

  describe "pipeline composition" do
    test "halts on the first rejection and never reaches later policies" do
      configure_policies(["drop", "noOp"])

      assert {:error, {:mrf_rejected, _}} = Inbox.process(create_activity())
    end

    test "default config (no policies) accepts everything via NoOpPolicy" do
      configure_policies([])

      assert {:ok, _} = Inbox.process(create_activity())
    end
  end
end
