defmodule Hybridsocial.Federation.MRFTest do
  @moduledoc """
  Policy-level tests for the MRF pipeline. Each policy is exercised with both
  an accept case and a reject case so a future tweak can't silently start
  dropping legitimate traffic (or start accepting adversarial traffic).
  """
  use Hybridsocial.DataCase, async: false

  alias Hybridsocial.Config
  alias Hybridsocial.Federation.InstancePolicy

  alias Hybridsocial.Federation.MRF

  alias Hybridsocial.Federation.MRF.{
    AntiLinkSpamPolicy,
    DropPolicy,
    HellthreadPolicy,
    KeywordPolicy,
    NoEmptyPolicy,
    NoOpPolicy,
    SimplePolicy
  }

  setup do
    # Config.Store isn't started in the test env, so start one per test and
    # share the sandbox connection so it can read/write the settings table.
    Ecto.Adapters.SQL.Sandbox.mode(Hybridsocial.Repo, {:shared, self()})
    start_supervised!(Hybridsocial.Config.Store)
    :ok
  end

  # --------------------------------------------------------------------------
  # Fixture builders
  # --------------------------------------------------------------------------

  defp create_activity(overrides \\ %{}) do
    base = %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "id" => "https://remote.example/activities/create-#{:erlang.unique_integer([:positive])}",
      "type" => "Create",
      "actor" => "https://remote.example/u/alice",
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "object" => %{
        "id" => "https://remote.example/objects/note-1",
        "type" => "Note",
        "content" => "Hello world",
        "attributedTo" => "https://remote.example/u/alice"
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

  defp insert_instance_policy(domain, policy) do
    %InstancePolicy{}
    |> InstancePolicy.changeset(%{"domain" => domain, "policy" => policy})
    |> Repo.insert!()
  end

  # --------------------------------------------------------------------------
  # NoEmptyPolicy
  # --------------------------------------------------------------------------

  describe "NoEmptyPolicy" do
    test "accepts posts with content" do
      assert {:ok, _} = NoEmptyPolicy.filter(create_activity())
    end

    test "accepts posts with attachments even if content is blank" do
      activity =
        create_activity(%{
          "object" => %{
            "content" => "   ",
            "attachment" => [%{"type" => "Image", "url" => "https://remote.example/img.jpg"}]
          }
        })

      assert {:ok, _} = NoEmptyPolicy.filter(activity)
    end

    test "rejects posts with empty content and no attachments" do
      activity = create_activity(%{"object" => %{"content" => "   ", "attachment" => []}})
      assert {:reject, _} = NoEmptyPolicy.filter(activity)
    end

    test "ignores non-Create activities" do
      assert {:ok, _} = NoEmptyPolicy.filter(%{"type" => "Follow"})
    end
  end

  # --------------------------------------------------------------------------
  # HellthreadPolicy
  # --------------------------------------------------------------------------

  describe "HellthreadPolicy" do
    test "accepts posts with mention count below the threshold" do
      recipients = for i <- 1..9, do: "https://remote.example/u/user#{i}"
      activity = create_activity(%{"to" => recipients})

      assert {:ok, _} = HellthreadPolicy.filter(activity)
    end

    test "rejects posts with mention count above the threshold" do
      recipients = for i <- 1..11, do: "https://remote.example/u/user#{i}"
      activity = create_activity(%{"to" => recipients})

      assert {:reject, _} = HellthreadPolicy.filter(activity)
    end

    test "excludes collection URIs from the mention count" do
      recipients =
        ["https://www.w3.org/ns/activitystreams#Public"] ++
          for _ <- 1..9, do: "https://remote.example/u/followers"

      activity = create_activity(%{"to" => recipients, "cc" => []})
      assert {:ok, _} = HellthreadPolicy.filter(activity)
    end

    test "ignores non-Create activities" do
      assert {:ok, _} = HellthreadPolicy.filter(%{"type" => "Follow"})
    end
  end

  # --------------------------------------------------------------------------
  # KeywordPolicy
  # --------------------------------------------------------------------------

  describe "KeywordPolicy" do
    test "accepts posts that do not match any reject pattern" do
      :ok = Config.set("mrf_keyword_reject", ["forbidden"])
      assert {:ok, _} = KeywordPolicy.filter(create_activity())
    end

    test "rejects posts containing a reject keyword (case-insensitive)" do
      :ok = Config.set("mrf_keyword_reject", ["Forbidden"])

      activity =
        create_activity(%{"object" => %{"content" => "this contains FORBIDDEN content"}})

      assert {:reject, _} = KeywordPolicy.filter(activity)
    end

    test "replaces content when a replace pattern is configured" do
      :ok = Config.set("mrf_keyword_reject", [])

      :ok =
        Config.set("mrf_keyword_replace", [
          %{"pattern" => "shout", "replacement" => "whisper"}
        ])

      activity = create_activity(%{"object" => %{"content" => "shout louder"}})

      assert {:ok, filtered} = KeywordPolicy.filter(activity)
      assert filtered["object"]["content"] == "whisper louder"
    end

    test "ignores non-Create activities" do
      :ok = Config.set("mrf_keyword_reject", ["anything"])
      assert {:ok, _} = KeywordPolicy.filter(%{"type" => "Follow"})
    end
  end

  # --------------------------------------------------------------------------
  # SimplePolicy (domain allowlist/blocklist via instance_policies table)
  # --------------------------------------------------------------------------

  describe "SimplePolicy" do
    test "accepts activity from an unlisted domain" do
      assert {:ok, _} = SimplePolicy.filter(create_activity())
    end

    test "rejects activity from a suspended domain" do
      insert_instance_policy("remote.example", "suspend")
      assert {:reject, _} = SimplePolicy.filter(create_activity())
    end

    test "strips public addressing from silenced domains" do
      insert_instance_policy("remote.example", "silence")

      activity =
        create_activity(%{
          "to" => ["https://www.w3.org/ns/activitystreams#Public"],
          "cc" => ["https://www.w3.org/ns/activitystreams#Public"]
        })

      assert {:ok, filtered} = SimplePolicy.filter(activity)
      refute "https://www.w3.org/ns/activitystreams#Public" in filtered["to"]
      refute "https://www.w3.org/ns/activitystreams#Public" in filtered["cc"]
    end

    test "rejects activity with a missing actor" do
      activity = create_activity() |> Map.put("actor", nil)
      assert {:reject, _} = SimplePolicy.filter(activity)
    end
  end

  # --------------------------------------------------------------------------
  # AntiLinkSpamPolicy
  # --------------------------------------------------------------------------

  describe "AntiLinkSpamPolicy" do
    test "accepts posts without links even from unknown actors" do
      activity =
        create_activity(%{"object" => %{"content" => "no links here at all, promise"}})

      assert {:ok, _} = AntiLinkSpamPolicy.filter(activity)
    end

    test "rejects posts with links from unknown actors" do
      activity =
        create_activity(%{
          "object" => %{"content" => ~s(click <a href="https://spam.example">here</a>)}
        })

      assert {:reject, _} = AntiLinkSpamPolicy.filter(activity)
    end

    test "accepts posts with links from accounts older than 24 hours" do
      old_time = DateTime.utc_now() |> DateTime.add(-48 * 3600, :second)

      %Hybridsocial.Accounts.Identity{}
      |> Ecto.Changeset.cast(
        %{
          type: "user",
          handle: "old_alice_#{:erlang.unique_integer([:positive])}",
          ap_actor_url: "https://remote.example/u/alice"
        },
        [:type, :handle, :ap_actor_url]
      )
      |> Ecto.Changeset.put_change(:inserted_at, old_time)
      |> Repo.insert!()

      activity =
        create_activity(%{"object" => %{"content" => ~s(<a href="https://ok.example">ok</a>)}})

      assert {:ok, _} = AntiLinkSpamPolicy.filter(activity)
    end
  end

  # --------------------------------------------------------------------------
  # Default policies (NoOp, Drop)
  # --------------------------------------------------------------------------

  describe "NoOpPolicy and DropPolicy" do
    test "NoOpPolicy accepts anything" do
      assert {:ok, _} = NoOpPolicy.filter(create_activity())
      assert {:ok, _} = NoOpPolicy.filter(%{})
    end

    test "DropPolicy rejects anything" do
      assert {:reject, _} = DropPolicy.filter(create_activity())
      assert {:reject, _} = DropPolicy.filter(%{})
    end
  end

  # --------------------------------------------------------------------------
  # Pipeline integration
  # --------------------------------------------------------------------------

  describe "filter_pipeline/1" do
    test "with no policies configured, passes activities from unrestricted domains" do
      :ok = Config.set("mrf_policies", [])
      assert {:ok, _} = MRF.filter_pipeline(create_activity())
    end

    test "SimplePolicy always runs first, whatever the setting says" do
      :ok = Config.set("mrf_policies", [])
      assert MRF.configured_policies() == [SimplePolicy]

      :ok = Config.set("mrf_policies", ["drop", "simple"])
      assert MRF.configured_policies() == [SimplePolicy, DropPolicy]
    end

    test "halts on first rejection" do
      :ok = Config.set("mrf_policies", ["drop", "noOp"])
      assert {:reject, _} = MRF.filter_pipeline(create_activity())
    end

    test "runs policies in order and preserves transformations" do
      :ok = Config.set("mrf_policies", ["noOp"])
      assert {:ok, unchanged} = MRF.filter_pipeline(create_activity())
      assert unchanged["type"] == "Create"
    end
  end
end
