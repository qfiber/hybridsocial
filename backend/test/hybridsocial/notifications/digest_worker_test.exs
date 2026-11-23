defmodule Hybridsocial.Notifications.DigestWorkerTest do
  # async: false — writes runtime config to the shared Config.Store.
  use Hybridsocial.DataCase, async: false

  alias Hybridsocial.{Config, Notifications, Repo}
  alias Hybridsocial.Accounts.User
  alias Hybridsocial.Notifications.DigestWorker

  @day 86_400

  setup do
    start_supervised!(Hybridsocial.Config.Store)
    Config.set("notification_digest_enabled", true)

    %{actor: create_trusted_user("digestactor")}
  end

  defp opt_in(identity, frequency) do
    user = Repo.get!(User, identity.id)

    user
    |> Ecto.Changeset.change(
      preferences: Map.put(user.preferences, "notification_digest", frequency)
    )
    |> Repo.update!()
  end

  defp notify(recipient, actor) do
    {:ok, n} = Notifications.notify_follow(actor.id, recipient.id)
    n
  end

  defp digest_at(identity), do: Repo.get!(User, identity.id).notification_digest_at

  defp from_now(seconds), do: DateTime.add(DateTime.utc_now(), seconds, :second)

  # Registration sends confirmation emails too, so drain the mailbox and keep
  # only the digests (subject "...: you have N new notification(s)").
  defp digest_subjects(acc \\ []) do
    receive do
      {:email, %Swoosh.Email{subject: subject}} ->
        digest_subjects(if subject =~ "new notification", do: [subject | acc], else: acc)
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "sends one digest of unread notifications to an opted-in user", %{actor: actor} do
    alice = create_user("digestalice")
    opt_in(alice, "daily")
    notify(alice, actor)

    assert DigestWorker.run_once() == 1
    assert [subject] = digest_subjects()
    assert subject =~ "1 new notification"
    assert digest_at(alice)
  end

  test "does not resend the same window", %{actor: actor} do
    alice = create_user("digestalice")
    opt_in(alice, "daily")
    notify(alice, actor)

    assert DigestWorker.run_once() == 1
    assert [_] = digest_subjects()

    # Not due again yet, even with a new notification.
    notify(alice, create_user("digestother"))
    assert DigestWorker.run_once() == 0
    assert digest_subjects() == []

    # A day later only the notification since the last digest is included.
    assert DigestWorker.run_once(from_now(@day)) == 1
    assert [subject] = digest_subjects()
    assert subject =~ "1 new notification"
  end

  test "a weekly user is not due after a day", %{actor: actor} do
    alice = create_user("digestalice")
    opt_in(alice, "weekly")
    notify(alice, actor)
    assert DigestWorker.run_once() == 1

    notify(alice, create_user("digestother"))
    assert DigestWorker.run_once(from_now(@day)) == 0
    assert DigestWorker.run_once(from_now(7 * @day)) == 1
  end

  test "skips users with nothing unread but stamps them", %{actor: actor} do
    alice = create_user("digestalice")
    opt_in(alice, "daily")
    notify(alice, actor)
    Notifications.mark_all_read(alice.id)

    assert DigestWorker.run_once() == 0
    assert digest_subjects() == []
    assert digest_at(alice)
  end

  test "skips users who have not opted in", %{actor: actor} do
    off = create_user("digestoff")
    opt_in(off, "off")
    notify(off, actor)
    notify(create_user("digestunset"), actor)

    assert DigestWorker.run_once() == 0
    assert digest_subjects() == []
  end

  test "skips suspended and unconfirmed accounts", %{actor: actor} do
    suspended = create_user("digestsusp")
    opt_in(suspended, "daily")
    notify(suspended, actor)

    suspended
    |> Ecto.Changeset.change(suspended_at: DateTime.utc_now())
    |> Repo.update!()

    unconfirmed = create_unconfirmed_user("digestunconf")
    opt_in(unconfirmed, "daily")
    notify(unconfirmed, actor)

    assert DigestWorker.run_once() == 0
    assert digest_subjects() == []
  end

  test "the instance switch turns digests off", %{actor: actor} do
    alice = create_user("digestalice")
    opt_in(alice, "daily")
    notify(alice, actor)
    Config.set("notification_digest_enabled", false)

    assert DigestWorker.run_once() == 0
    assert digest_subjects() == []
    refute digest_at(alice)
  end
end
