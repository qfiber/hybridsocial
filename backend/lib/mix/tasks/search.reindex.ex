defmodule Mix.Tasks.Hybridsocial.Search.Reindex do
  @moduledoc "Reindexes all data into OpenSearch."
  @shortdoc "Reindex all data into OpenSearch"

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    IO.puts("Setting up OpenSearch indexes...")
    Hybridsocial.Search.Indexer.setup_indexes()
    IO.puts("Reindexing all data...")
    Hybridsocial.Search.Indexer.reindex_all()
    IO.puts("Done.")
  end
end
