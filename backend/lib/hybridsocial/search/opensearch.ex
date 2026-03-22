defmodule Hybridsocial.Search.OpenSearch do
  @moduledoc "OpenSearch REST API client."

  require Logger

  # --- Index Management ---

  @doc "Creates an index with the given mapping."
  def create_index(index_name, mapping) do
    case request(:put, "/#{index_name}", mapping) do
      {:ok, %{status_code: status}} when status in [200, 201] ->
        :ok

      {:ok, %{status_code: 400, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"error" => %{"type" => "resource_already_exists_exception"}}} -> :ok
          _ -> {:error, body}
        end

      {:ok, %{body: body}} ->
        {:error, body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Deletes an index."
  def delete_index(index_name) do
    case request(:delete, "/#{index_name}") do
      {:ok, %{status_code: 200}} -> :ok
      {:ok, %{status_code: 404}} -> :ok
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Checks if an index exists."
  def index_exists?(index_name) do
    case request(:head, "/#{index_name}") do
      {:ok, %{status_code: 200}} -> true
      _ -> false
    end
  end

  # --- Document Operations ---

  @doc "Indexes a single document."
  def index_document(index_name, id, document) do
    case request(:put, "/#{index_name}/_doc/#{id}", document) do
      {:ok, %{status_code: status}} when status in [200, 201] -> :ok
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Deletes a single document."
  def delete_document(index_name, id) do
    case request(:delete, "/#{index_name}/_doc/#{id}") do
      {:ok, %{status_code: 200}} -> :ok
      {:ok, %{status_code: 404}} -> :ok
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Bulk indexes documents. Each document must have an :id field."
  def bulk_index(index_name, documents) when is_list(documents) do
    if documents == [] do
      :ok
    else
      body =
        documents
        |> Enum.flat_map(fn doc ->
          {id, fields} = Map.pop(doc, :id)
          action = Jason.encode!(%{index: %{_index: index_name, _id: id}})
          data = Jason.encode!(fields)
          [action, data]
        end)
        |> Enum.join("\n")

      body = body <> "\n"

      case request(:post, "/_bulk", body, content_type: "application/x-ndjson") do
        {:ok, %{status_code: 200, body: resp_body}} ->
          case Jason.decode(resp_body) do
            {:ok, %{"errors" => false}} -> :ok
            {:ok, %{"errors" => true} = resp} -> {:error, resp}
            _ -> :ok
          end

        {:ok, %{body: resp_body}} ->
          {:error, resp_body}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # --- Search ---

  @doc "Executes a search query against an index."
  def search(index_name, query, opts \\ []) do
    size = Keyword.get(opts, :size, 20)
    from = Keyword.get(opts, :from, 0)

    body = Map.merge(query, %{size: size, from: from})

    case request(:post, "/#{index_name}/_search", body) do
      {:ok, %{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"hits" => %{"hits" => hits, "total" => total}} = resp} ->
            total_count =
              case total do
                %{"value" => v} -> v
                n when is_integer(n) -> n
                _ -> 0
              end

            parsed_hits =
              Enum.map(hits, fn hit ->
                %{
                  id: hit["_id"],
                  score: hit["_score"],
                  source: hit["_source"]
                }
              end)

            aggregations = Map.get(resp, "aggregations", %{})

            {:ok, %{hits: parsed_hits, total: total_count, aggregations: aggregations}}

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, %{body: resp_body}} ->
        {:error, resp_body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Helpers ---

  defp base_url do
    Application.get_env(:hybridsocial, :opensearch_url, "http://localhost:9200")
  end

  defp request(method, path, body \\ nil, opts \\ []) do
    url = base_url() <> path

    headers =
      case Keyword.get(opts, :content_type) do
        nil -> [{"Content-Type", "application/json"}]
        ct -> [{"Content-Type", ct}]
      end

    encoded_body =
      case body do
        nil -> ""
        b when is_binary(b) -> b
        b -> Jason.encode!(b)
      end

    HTTPoison.request(method, url, encoded_body, headers, recv_timeout: 15_000)
  end
end
