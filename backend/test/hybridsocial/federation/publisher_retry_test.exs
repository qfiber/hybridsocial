defmodule Hybridsocial.Federation.PublisherRetryTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Federation.{CircuitBreaker, Delivery, Publisher}
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.Posts

  @inbox "https://peer.example/users/bob/inbox"

  setup do
    %{actor: create_user("retrier")}
  end

  defp ago(seconds), do: DateTime.add(DateTime.utc_now(), -seconds, :second)

  defp delivery!(actor, attrs) do
    defaults = %{
      activity_id: "https://local.test/activities/#{Ecto.UUID.generate()}",
      activity_type: "Create",
      actor_id: actor.id,
      target_inbox: @inbox,
      status: "failed",
      attempts: 1,
      last_attempt_at: ago(3600),
      error: "Connection error: :timeout",
      inserted_at: ago(3600),
      updated_at: ago(3600)
    }

    attrs = Map.merge(defaults, attrs)

    body =
      Map.get(attrs, :activity_body, %{"id" => attrs.activity_id, "type" => attrs.activity_type})

    Repo.insert!(struct(Delivery, Map.put(attrs, :activity_body, body)))
  end

  defp reload(d), do: Repo.get!(Delivery, d.id)

  test "re-queues a transient failure whose backoff has elapsed", %{actor: actor} do
    d = delivery!(actor, %{})
    Publisher.retry_failed_deliveries()
    assert reload(d).status == "retrying"
  end

  test "leaves a peer's 4xx refusal alone", %{actor: actor} do
    d = delivery!(actor, %{error: "HTTP 403: {\"error\":\"nope\"}"})
    Publisher.retry_failed_deliveries()
    assert %Delivery{status: "failed", attempts: 1} = reload(d)
  end

  test "leaves rows older than the retry window", %{actor: actor} do
    d = delivery!(actor, %{inserted_at: ago(3 * 86_400), updated_at: ago(3 * 86_400)})
    Publisher.retry_failed_deliveries()
    assert reload(d).status == "failed"
  end

  test "waits out the backoff", %{actor: actor} do
    # attempts 1 -> 300s backoff; last attempt a minute ago.
    d = delivery!(actor, %{last_attempt_at: ago(60)})
    Publisher.retry_failed_deliveries()
    assert reload(d).status == "failed"
  end

  test "stops at the attempt cap", %{actor: actor} do
    d = delivery!(actor, %{attempts: 6})
    Publisher.retry_failed_deliveries()
    assert reload(d).status == "failed"
  end

  test "leaves an admin-disabled peer's rows parked", %{actor: actor} do
    :ok = CircuitBreaker.disable_delivery("peer.example")
    d = delivery!(actor, %{})
    Publisher.retry_failed_deliveries()
    assert reload(d).status == "failed"
  end

  test "retires a Create whose post has since been deleted", %{actor: actor} do
    {:ok, post} = Posts.create_post(actor.id, %{"content" => "gone"})
    {:ok, _} = Posts.delete_post(post.id, actor.id)

    d =
      delivery!(actor, %{
        activity_body: %{
          "id" => "https://local.test/a/1",
          "type" => "Create",
          "object" => %{"id" => post.ap_id}
        }
      })

    Publisher.retry_failed_deliveries()
    assert %Delivery{status: "failed", attempts: 6, error: "Obsolete" <> _} = reload(d)
  end

  test "retires an activity a later Undo to the same inbox cancelled", %{actor: actor} do
    like =
      delivery!(actor, %{
        activity_type: "Like",
        activity_id: "https://local.test/likes/1",
        activity_body: %{"id" => "https://local.test/likes/1", "type" => "Like"},
        inserted_at: ago(7200),
        updated_at: ago(7200)
      })

    _undo =
      delivery!(actor, %{
        activity_type: "Undo",
        status: "delivered",
        error: nil,
        activity_body: %{
          "id" => "https://local.test/undo/1",
          "type" => "Undo",
          "object" => %{"id" => "https://local.test/likes/1", "type" => "Like"}
        }
      })

    Publisher.retry_failed_deliveries()
    assert %Delivery{status: "failed", error: "Obsolete" <> _} = reload(like)
  end

  test "picks a stuck in-flight row back up, but not a fresh one", %{actor: actor} do
    stuck = delivery!(actor, %{status: "retrying", updated_at: ago(3600)})
    fresh = delivery!(actor, %{status: "retrying", updated_at: ago(30)})
    Publisher.retry_failed_deliveries()
    assert reload(stuck).status == "retrying" and reload(stuck).updated_at != stuck.updated_at
    assert reload(fresh).updated_at == fresh.updated_at
  end

  test "transient_error?/1 classifies what a retry can fix" do
    for e <- [
          "Connection error: :timeout",
          "Skipped: instance circuit open",
          "HTTP 503: x",
          "HTTP 500: x",
          "HTTP 429: x",
          "HTTP 408: x"
        ],
        do: assert(Publisher.transient_error?(e), e)

    for e <- [
          "HTTP 400: x",
          "HTTP 403: x",
          "HTTP 404: x",
          "HTTP 410: x",
          "HTTP 501: x",
          "Obsolete",
          nil
        ],
        do: refute(Publisher.transient_error?(e), inspect(e))
  end
end
