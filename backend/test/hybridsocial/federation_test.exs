defmodule Hybridsocial.FederationTest do
  use Hybridsocial.DataCase, async: false

  alias Hybridsocial.Federation
  alias Hybridsocial.Federation.Dedup

  describe "cache_remote_actor/1" do
    test "inserts a new remote actor" do
      attrs = %{
        ap_id: "https://remote.example/users/alice",
        handle: "alice",
        domain: "remote.example",
        display_name: "Alice",
        inbox_url: "https://remote.example/users/alice/inbox",
        public_key: "-----BEGIN PUBLIC KEY-----\ntest\n-----END PUBLIC KEY-----"
      }

      assert {:ok, actor} = Federation.cache_remote_actor(attrs)
      assert actor.ap_id == "https://remote.example/users/alice"
      assert actor.handle == "alice"
      assert actor.domain == "remote.example"
      assert actor.last_fetched_at != nil
    end

    test "upserts on conflict" do
      attrs = %{
        ap_id: "https://remote.example/users/bob",
        handle: "bob",
        domain: "remote.example"
      }

      assert {:ok, actor1} = Federation.cache_remote_actor(attrs)

      updated_attrs = Map.put(attrs, :display_name, "Bob Updated")
      assert {:ok, actor2} = Federation.cache_remote_actor(updated_attrs)

      assert actor1.id == actor2.id
      assert actor2.display_name == "Bob Updated"
    end
  end

  describe "instance policies" do
    test "set_instance_policy/4 creates a policy" do
      assert {:ok, policy} =
               Federation.set_instance_policy("bad.example", "suspend", "spam", nil)

      assert policy.domain == "bad.example"
      assert policy.policy == "suspend"
      assert policy.reason == "spam"
    end

    test "set_instance_policy/4 updates existing policy" do
      {:ok, _} = Federation.set_instance_policy("bad.example", "silence", "minor issues", nil)
      {:ok, policy} = Federation.set_instance_policy("bad.example", "suspend", "spam", nil)

      assert policy.policy == "suspend"
      assert policy.reason == "spam"
    end

    test "get_instance_policy/1 returns the policy" do
      {:ok, _} = Federation.set_instance_policy("test.example", "allow", nil, nil)
      policy = Federation.get_instance_policy("test.example")

      assert policy.domain == "test.example"
      assert policy.policy == "allow"
    end

    test "get_instance_policy/1 returns nil for unknown domain" do
      assert Federation.get_instance_policy("unknown.example") == nil
    end

    test "delete_instance_policy/1 removes the policy" do
      {:ok, _} = Federation.set_instance_policy("delete.example", "allow", nil, nil)
      assert {:ok, _} = Federation.delete_instance_policy("delete.example")
      assert Federation.get_instance_policy("delete.example") == nil
    end

    test "delete_instance_policy/1 returns error for missing domain" do
      assert {:error, :not_found} = Federation.delete_instance_policy("nonexistent.example")
    end

    test "list_instance_policies/0 returns all policies" do
      {:ok, _} = Federation.set_instance_policy("a.example", "allow", nil, nil)
      {:ok, _} = Federation.set_instance_policy("b.example", "suspend", "bad", nil)

      policies = Federation.list_instance_policies()
      assert length(policies) >= 2
    end

    test "domain_allowed?/1 returns false for suspended domains" do
      {:ok, _} = Federation.set_instance_policy("suspended.example", "suspend", "bye", nil)
      refute Federation.domain_allowed?("suspended.example")
    end

    test "domain_allowed?/1 returns true for silenced domains" do
      {:ok, _} = Federation.set_instance_policy("silenced.example", "silence", "quiet", nil)
      assert Federation.domain_allowed?("silenced.example")
    end

    test "domain_allowed?/1 returns true for unknown domains" do
      assert Federation.domain_allowed?("new.example")
    end
  end

  describe "delivery tracking" do
    test "record_delivery/1 creates a delivery" do
      attrs = %{
        activity_id: "https://local.example/activities/1",
        actor_id: Ecto.UUID.generate(),
        target_inbox: "https://remote.example/inbox",
        status: "pending"
      }

      assert {:ok, delivery} = Federation.record_delivery(attrs)
      assert delivery.activity_id == attrs.activity_id
      assert delivery.status == "pending"
      assert delivery.attempts == 0
    end

    test "update_delivery/2 updates a delivery" do
      {:ok, delivery} =
        Federation.record_delivery(%{
          activity_id: "https://local.example/activities/2",
          target_inbox: "https://remote.example/inbox"
        })

      assert {:ok, updated} =
               Federation.update_delivery(delivery.id, %{
                 status: "delivered",
                 attempts: 1,
                 last_attempt_at: DateTime.utc_now()
               })

      assert updated.status == "delivered"
      assert updated.attempts == 1
    end

    test "update_delivery/2 returns error for missing delivery" do
      assert {:error, :not_found} =
               Federation.update_delivery(Ecto.UUID.generate(), %{status: "delivered"})
    end
  end

  describe "deduplication" do
    test "deduplicate?/1 returns false for new hash" do
      refute Federation.deduplicate?("newhash123")
    end

    test "deduplicate?/1 returns true for existing hash" do
      Federation.record_dedup("existinghash", "https://example.com/activity/1")
      assert Federation.deduplicate?("existinghash")
    end

    test "record_dedup/2 stores a dedup record" do
      assert {:ok, dedup} = Federation.record_dedup("hash123", "https://example.com/activity/2")
      assert dedup.activity_hash == "hash123"
      assert dedup.activity_id == "https://example.com/activity/2"
      assert dedup.processed_at != nil
      assert dedup.expires_at != nil
    end

    test "cleanup_expired_dedup/0 removes expired entries" do
      # Insert an expired entry directly
      past = DateTime.add(DateTime.utc_now(), -86_400, :second)

      Repo.insert!(%Dedup{
        activity_hash: "expired_hash",
        activity_id: "https://example.com/old",
        processed_at: past,
        expires_at: past
      })

      assert Federation.deduplicate?("expired_hash")
      {:ok, count} = Federation.cleanup_expired_dedup()
      assert count >= 1
      refute Federation.deduplicate?("expired_hash")
    end
  end
end
