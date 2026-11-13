defmodule Hybridsocial.Repo.Migrations.WidenFederationUrlColumns do
  use Ecto.Migration

  # Remote servers send ids and URLs of any length; at varchar(255) a longer
  # one raised on insert and 500'd the inbox, so the post was dropped and the
  # sender retried forever (#267). `posts.spoiler_text` was also narrower than
  # the 500 the changeset allows.
  #
  # varchar(n) -> text is binary-coercible in Postgres: no table rewrite and
  # no index rebuild. Length caps live in the changesets instead.
  @columns [
    posts: [:ap_id, :spoiler_text],
    post_drafts: [:spoiler_text],
    messages: [:ap_id],
    remote_actors: [
      :ap_id,
      :avatar_url,
      :followers_url,
      :inbox_url,
      :outbox_url,
      :shared_inbox_url
    ],
    groups: [:ap_actor_url],
    federation_deliveries: [:target_inbox],
    relays: [:actor_url, :inbox_url]
  ]

  def change do
    for {table, columns} <- @columns do
      alter table(table) do
        for column <- columns do
          modify column, :text, from: {:string, size: 255}
        end
      end
    end
  end
end
