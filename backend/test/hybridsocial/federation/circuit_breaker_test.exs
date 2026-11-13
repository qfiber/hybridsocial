defmodule Hybridsocial.Federation.CircuitBreakerTest do
  use Hybridsocial.DataCase, async: true

  import Ecto.Query, only: [from: 2]

  alias Hybridsocial.Federation.{CircuitBreaker, RemoteInstance}
  alias Hybridsocial.Repo

  @inbox "https://dead.example/users/x/inbox"

  defp inst, do: Repo.get_by(RemoteInstance, domain: "dead.example")

  test "healthy/unknown instance always allows delivery" do
    assert CircuitBreaker.allow?(@inbox)
    # Unparseable inbox -> nil domain -> fail open, never block a real delivery.
    assert CircuitBreaker.allow?("not a url")
  end

  test "hard failures below threshold count but keep the circuit closed" do
    for _ <- 1..4, do: CircuitBreaker.record_result(@inbox, :hard)
    assert CircuitBreaker.allow?(@inbox)
    assert inst().consecutive_failures == 4
    assert is_nil(inst().circuit_reopen_at)
  end

  test "threshold consecutive hard failures opens the circuit" do
    for _ <- 1..5, do: CircuitBreaker.record_result(@inbox, :hard)
    refute CircuitBreaker.allow?(@inbox)
    i = inst()
    assert i.consecutive_failures == 5
    assert i.unreachable_since
    assert DateTime.compare(i.circuit_reopen_at, DateTime.utc_now()) == :gt
  end

  test "soft (HTTP status) failures never open the circuit" do
    for _ <- 1..10, do: CircuitBreaker.record_result(@inbox, :soft)
    assert CircuitBreaker.allow?(@inbox)
    # A pure soft failure doesn't even create a row — the server is up.
    assert is_nil(inst())
  end

  test "a success resets failures and closes an open circuit" do
    for _ <- 1..5, do: CircuitBreaker.record_result(@inbox, :hard)
    refute CircuitBreaker.allow?(@inbox)

    CircuitBreaker.record_result(@inbox, :ok)

    assert CircuitBreaker.allow?(@inbox)
    i = inst()
    assert i.consecutive_failures == 0
    assert is_nil(i.circuit_reopen_at)
    assert is_nil(i.unreachable_since)
  end

  test "half-open: once the reopen time passes, one probe is allowed and a fresh failure re-opens further out" do
    for _ <- 1..5, do: CircuitBreaker.record_result(@inbox, :hard)
    refute CircuitBreaker.allow?(@inbox)

    # Simulate the probe window arriving.
    past = DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:microsecond)
    inst() |> RemoteInstance.changeset(%{circuit_reopen_at: past}) |> Repo.update!()

    assert CircuitBreaker.allow?(@inbox)

    # Probe fails again -> failures escalate, reopen pushed back into the future.
    CircuitBreaker.record_result(@inbox, :hard)
    i = inst()
    assert i.consecutive_failures == 6
    assert DateTime.compare(i.circuit_reopen_at, DateTime.utc_now()) == :gt
  end

  describe "admin delivery kill switch" do
    test "disabling delivery blocks it with no probe window" do
      assert CircuitBreaker.allow?(@inbox)

      :ok = CircuitBreaker.disable_delivery("dead.example", reason: "instance shut down")

      refute CircuitBreaker.allow?(@inbox)
      assert CircuitBreaker.delivery_disabled?("dead.example")
      assert inst().delivery_disabled_reason == "instance shut down"
      # No reopen time was set — this one never re-probes on its own.
      assert is_nil(inst().circuit_reopen_at)
    end

    test "the kill switch outranks a half-open probe window" do
      for _ <- 1..5, do: CircuitBreaker.record_result(@inbox, :hard)
      :ok = CircuitBreaker.disable_delivery("dead.example")

      # Probe window arrives; the breaker alone would allow one attempt.
      past = DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:microsecond)
      inst() |> RemoteInstance.changeset(%{circuit_reopen_at: past}) |> Repo.update!()

      refute CircuitBreaker.allow?(@inbox)
    end

    test "re-enabling clears the switch and the breaker state" do
      for _ <- 1..5, do: CircuitBreaker.record_result(@inbox, :hard)
      :ok = CircuitBreaker.disable_delivery("dead.example", reason: "gone")
      refute CircuitBreaker.allow?(@inbox)

      :ok = CircuitBreaker.enable_delivery("dead.example")

      assert CircuitBreaker.allow?(@inbox)
      i = inst()
      assert is_nil(i.delivery_disabled_at)
      assert is_nil(i.delivery_disabled_reason)
      assert i.consecutive_failures == 0
      assert is_nil(i.circuit_reopen_at)
    end

    test "disable_delivery is case-insensitive and works for an unknown peer" do
      :ok = CircuitBreaker.disable_delivery("DEAD.example")

      refute CircuitBreaker.allow?(@inbox)
      assert MapSet.member?(CircuitBreaker.disabled_domains(), "dead.example")
      assert [%{domain: "dead.example"}] = CircuitBreaker.list_disabled()
    end

    test "other domains are unaffected" do
      :ok = CircuitBreaker.disable_delivery("dead.example")

      assert CircuitBreaker.allow?("https://live.example/inbox")
      refute CircuitBreaker.delivery_disabled?("live.example")
    end
  end

  describe "blocked_domains/0" do
    test "covers admin-disabled peers and open circuits, not due or healthy ones" do
      :ok = CircuitBreaker.disable_delivery("off.example")
      for _ <- 1..5, do: CircuitBreaker.record_result(@inbox, :hard)
      for _ <- 1..5, do: CircuitBreaker.record_result("https://due.example/inbox", :hard)
      CircuitBreaker.record_result("https://fine.example/inbox", :ok)

      Repo.update_all(
        from(r in RemoteInstance, where: r.domain == "due.example"),
        set: [circuit_reopen_at: DateTime.add(DateTime.utc_now(), -60, :second)]
      )

      blocked = CircuitBreaker.blocked_domains()
      assert MapSet.member?(blocked, "off.example")
      assert MapSet.member?(blocked, "dead.example")
      refute MapSet.member?(blocked, "due.example")
      refute MapSet.member?(blocked, "fine.example")
    end
  end
end
