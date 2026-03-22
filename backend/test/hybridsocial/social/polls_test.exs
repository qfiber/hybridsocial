defmodule Hybridsocial.Social.PollsTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Social.{Polls, Posts}

  defp create_user(handle, email) do
    {:ok, identity} =
      Hybridsocial.Accounts.register_user(%{
        "handle" => handle,
        "email" => email,
        "password" => "password123",
        "password_confirmation" => "password123"
      })

    identity
  end

  defp create_poll_post(identity) do
    {:ok, post} =
      Posts.create_post(identity.id, %{
        "content" => "What is your favorite language?",
        "post_type" => "poll",
        "options" => ["Elixir", "Rust", "Go"],
        "multiple_choice" => false
      })

    poll = Polls.get_poll(post.id)
    {post, poll}
  end

  describe "create_poll/2" do
    test "creates a poll with options" do
      identity = create_user("poll_user1", "poll1@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Poll test"})

      assert {:ok, poll} =
               Polls.create_poll(post.id, %{
                 "options" => ["Option A", "Option B"],
                 "multiple_choice" => true
               })

      assert poll.multiple_choice == true
      assert length(poll.options) == 2
      assert hd(poll.options).text == "Option A"
    end

    test "creates poll with expires_at" do
      identity = create_user("poll_user2", "poll2@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Expiring poll"})

      future = DateTime.add(DateTime.utc_now(), 3600, :second)

      assert {:ok, poll} =
               Polls.create_poll(post.id, %{
                 "options" => ["Yes", "No"],
                 "expires_at" => future
               })

      assert poll.expires_at != nil
    end
  end

  describe "get_poll/1" do
    test "returns poll with options preloaded" do
      identity = create_user("poll_user3", "poll3@test.com")
      {post, _poll} = create_poll_post(identity)

      poll = Polls.get_poll(post.id)
      assert poll != nil
      assert length(poll.options) == 3
    end

    test "returns nil for non-existent poll" do
      assert Polls.get_poll(Ecto.UUID.generate()) == nil
    end
  end

  describe "vote/3" do
    test "casts a vote" do
      identity = create_user("poll_voter1", "voter1@test.com")
      {_post, poll} = create_poll_post(identity)

      option = hd(poll.options)
      assert {:ok, votes} = Polls.vote(poll.id, identity.id, [option.id])
      assert length(votes) == 1
    end

    test "updates vote counts" do
      identity = create_user("poll_voter2", "voter2@test.com")
      {post, poll} = create_poll_post(identity)

      option = hd(poll.options)
      {:ok, _} = Polls.vote(poll.id, identity.id, [option.id])

      updated_poll = Polls.get_poll(post.id)
      assert updated_poll.voters_count == 1

      voted_option = Enum.find(updated_poll.options, &(&1.id == option.id))
      assert voted_option.votes_count == 1
    end

    test "rejects vote on expired poll" do
      identity = create_user("poll_voter3", "voter3@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Expired poll"})

      past = DateTime.add(DateTime.utc_now(), -3600, :second)

      {:ok, poll} =
        Polls.create_poll(post.id, %{
          "options" => ["Yes", "No"],
          "expires_at" => past
        })

      option = hd(poll.options)
      assert {:error, :poll_expired} = Polls.vote(poll.id, identity.id, [option.id])
    end

    test "rejects duplicate vote on single-choice poll" do
      voter = create_user("poll_voter4", "voter4@test.com")
      creator = create_user("poll_creator4", "creator4@test.com")
      {_post, poll} = create_poll_post(creator)

      option1 = Enum.at(poll.options, 0)
      option2 = Enum.at(poll.options, 1)

      {:ok, _} = Polls.vote(poll.id, voter.id, [option1.id])
      assert {:error, :already_voted} = Polls.vote(poll.id, voter.id, [option2.id])
    end

    test "rejects vote with invalid option" do
      identity = create_user("poll_voter5", "voter5@test.com")
      {_post, poll} = create_poll_post(identity)

      fake_option_id = Ecto.UUID.generate()
      assert {:error, :invalid_options} = Polls.vote(poll.id, identity.id, [fake_option_id])
    end
  end

  describe "has_voted?/2" do
    test "returns true after voting" do
      identity = create_user("poll_voter6", "voter6@test.com")
      {_post, poll} = create_poll_post(identity)

      option = hd(poll.options)
      {:ok, _} = Polls.vote(poll.id, identity.id, [option.id])

      assert Polls.has_voted?(poll.id, identity.id)
    end

    test "returns false when not voted" do
      identity = create_user("poll_voter7", "voter7@test.com")
      {_post, poll} = create_poll_post(identity)

      refute Polls.has_voted?(poll.id, identity.id)
    end
  end

  describe "get_votes/2" do
    test "returns user's votes" do
      identity = create_user("poll_voter8", "voter8@test.com")
      {_post, poll} = create_poll_post(identity)

      option = hd(poll.options)
      {:ok, _} = Polls.vote(poll.id, identity.id, [option.id])

      votes = Polls.get_votes(poll.id, identity.id)
      assert length(votes) == 1
      assert hd(votes).option_id == option.id
    end
  end

  describe "poll_expired?/1" do
    test "returns false for poll without expiry" do
      identity = create_user("poll_exp1", "exp1@test.com")
      {_post, poll} = create_poll_post(identity)

      refute Polls.poll_expired?(poll)
    end

    test "returns true for expired poll" do
      identity = create_user("poll_exp2", "exp2@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Expired"})

      past = DateTime.add(DateTime.utc_now(), -3600, :second)

      {:ok, poll} =
        Polls.create_poll(post.id, %{
          "options" => ["A", "B"],
          "expires_at" => past
        })

      assert Polls.poll_expired?(poll)
    end

    test "returns false for non-expired poll" do
      identity = create_user("poll_exp3", "exp3@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Active"})

      future = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, poll} =
        Polls.create_poll(post.id, %{
          "options" => ["A", "B"],
          "expires_at" => future
        })

      refute Polls.poll_expired?(poll)
    end
  end
end
