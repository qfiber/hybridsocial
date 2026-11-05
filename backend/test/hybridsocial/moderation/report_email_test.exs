defmodule Hybridsocial.Moderation.ReportEmailTest do
  use Hybridsocial.DataCase, async: false

  import Swoosh.TestAssertions

  alias Hybridsocial.Config
  alias Hybridsocial.Moderation
  alias Hybridsocial.Notifications.Preference

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Hybridsocial.Repo, {:shared, self()})
    start_supervised!(Hybridsocial.Config.Store)
    Application.put_env(:swoosh, :shared_test_process, self())
    on_exit(fn -> Application.delete_env(:swoosh, :shared_test_process) end)

    ctx = %{
      admin: create_admin("re_admin", "re_admin@test.com"),
      reporter: create_user("re_reporter"),
      reported: create_user("re_reported")
    }

    flush_emails()
    ctx
  end

  # Registration sends confirmation emails, which aren't what's under test.
  defp flush_emails do
    receive do
      {:email, _} -> flush_emails()
    after
      0 -> :ok
    end
  end

  defp create_report(ctx, description \\ "they keep spamming", extra \\ %{}) do
    {:ok, report} =
      Moderation.create_report(
        ctx.reporter.id,
        Map.merge(
          %{
            "reported_id" => ctx.reported.id,
            "target_type" => "identity",
            "target_id" => ctx.reported.id,
            "category" => "spam",
            "description" => description
          },
          extra
        )
      )

    report
  end

  # Files a report with the switch off, so no background task races the test,
  # then runs the same fan-out the task would.
  defp notify(ctx, description \\ "they keep spamming", throttle \\ 0) do
    :ok = Config.set("report_email_throttle_seconds", throttle)
    report = create_report(ctx, description)
    :ok = Moderation.notify_staff_of_report(report)
    report
  end

  defp await_report_tasks do
    for pid <- Task.Supervisor.children(Hybridsocial.TaskSupervisor) do
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 5_000
    end
  end

  describe "the instance switch" do
    test "is off by default, so filing a report sends nothing", ctx do
      create_report(ctx)
      await_report_tasks()
      refute_email_sent()
    end

    test "sends nothing when turned off", ctx do
      :ok = Config.set("report_email_notifications_enabled", false)
      create_report(ctx)
      await_report_tasks()
      refute_email_sent()
    end

    test "turned on, filing a report emails staff with no individual opt-in", ctx do
      :ok = Config.set("report_email_notifications_enabled", true)
      create_report(ctx)

      assert_receive {:email, email}, 5_000
      await_report_tasks()

      assert [{_, "re_admin@test.com"}] = email.to
      assert email.subject =~ "spam"
      assert email.subject =~ "re_reporter"
    end

    test "turned on, a report federated in from another server also emails", ctx do
      :ok = Config.set("report_email_notifications_enabled", true)
      create_report(ctx, "from afar", %{"federated" => true})

      assert_receive {:email, email}, 5_000
      await_report_tasks()
      assert email.html_body =~ "from afar"
    end
  end

  test "includes the reporter's text, escaped", ctx do
    notify(ctx, "<script>alert(1)</script> spam")

    assert_receive {:email, email}
    assert email.html_body =~ "&lt;script&gt;"
    refute email.html_body =~ "<script>"
  end

  test "a staff member's stored preference still opts them out", ctx do
    %Preference{}
    |> Ecto.Changeset.change(
      identity_id: ctx.admin.id,
      type: "admin_new_report",
      email: false
    )
    |> Repo.insert!()

    notify(ctx)
    refute_email_sent()
  end

  test "doesn't email accounts without a staff role", ctx do
    Repo.delete_all(Hybridsocial.Auth.IdentityRole)

    notify(ctx)
    refute_email_sent()
  end

  test "a throttle of 0 sends one email per report", ctx do
    notify(ctx, "first", 0)
    assert_email_sent(fn email -> assert email.html_body =~ "first" end)
    notify(ctx, "second", 0)
    assert_email_sent(fn email -> assert email.html_body =~ "second" end)
  end

  test "the throttle limits each recipient, and the report is still filed", ctx do
    notify(ctx, "first", 60)
    assert_email_sent(fn email -> assert email.html_body =~ "first" end)

    second = notify(ctx, "second", 60)
    refute_email_sent()
    assert Repo.get!(Moderation.Report, second.id)
  end

  test "group-tier reports don't email instance staff" do
    assert :ok = Moderation.notify_staff_of_report(%Moderation.Report{tier: "group"})
    refute_email_sent()
  end
end
