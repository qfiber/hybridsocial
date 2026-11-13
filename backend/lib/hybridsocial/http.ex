defmodule Hybridsocial.HTTP do
  @moduledoc """
  Thin HTTP client wrapper over `Req` that preserves the `HTTPoison` call
  and return shape, so the ~125 former HTTPoison call sites keep working
  unchanged (bar the module name).

  Why it exists: HTTPoison drags in `hackney`, which is unmaintained and
  carried SSRF/CRLF/SSL-timeout CVEs (GHSA-pj7v-xfvx-wmjq et al.). Req runs
  on Finch (Mint) with no hackney.

  Semantics deliberately matched to HTTPoison, NOT Req defaults:
    * redirects are NOT followed unless `follow_redirect: true` (Req
      follows by default — an SSRF-relevant difference). When they are
      followed, the chain is capped at `max_redirect` (default 4, down
      from Req's default of 10) so a misconfigured or hostile peer can't
      send us around a long or looping chain.
    * no automatic retries (Req retries by default).
    * the body is returned raw (never auto-decoded) — callers Jason.decode
      themselves, as they did with HTTPoison.
    * response headers come back as a `[{name, value}]` list, not Req's map.

  Returns `{:ok, %Hybridsocial.HTTP.Response{}}` or
  `{:error, %Hybridsocial.HTTP.Error{}}`, mirroring HTTPoison's structs
  (fields `status_code`/`body`/`headers` and `reason`).
  """

  defmodule Response do
    @moduledoc false
    defstruct [:status_code, :body, :headers, :request_url]
  end

  defmodule Error do
    @moduledoc false
    defstruct [:reason, :id]
  end

  def get(url, headers \\ [], opts \\ []), do: request(:get, url, "", headers, opts)
  def delete(url, headers \\ [], opts \\ []), do: request(:delete, url, "", headers, opts)

  def post(url, body \\ "", headers \\ [], opts \\ []),
    do: request(:post, url, body, headers, opts)

  def put(url, body \\ "", headers \\ [], opts \\ []), do: request(:put, url, body, headers, opts)

  def request(method, url, body \\ "", headers \\ [], opts \\ []) do
    req_opts =
      [
        method: method,
        url: url,
        headers: headers,
        decode_body: false,
        retry: false,
        redirect: Keyword.get(opts, :follow_redirect, false),
        # Bound the redirect chain (Req's default is 10). Callers may pass a
        # lower `max_redirect`; anything past this stops rather than looping.
        max_redirects: Keyword.get(opts, :max_redirect, 4)
      ]
      |> maybe_put(:body, request_body(method, body))
      |> maybe_put(:params, Keyword.get(opts, :params))
      # Test seam: a `Req.Test` stub. Never passed in production code.
      |> maybe_put(:plug, Keyword.get(opts, :plug))
      |> put_receive_timeout(opts)
      |> put_connect_options(opts)

    try do
      case Req.request(req_opts) do
        {:ok, %Req.Response{status: status, body: rbody, headers: rheaders}} ->
          {:ok,
           %Response{
             status_code: status,
             body: to_binary(rbody),
             headers: to_header_list(rheaders),
             request_url: url
           }}

        {:error, exception} ->
          {:error, %Error{reason: error_reason(exception)}}
      end
    rescue
      # Req raises `RuntimeError "too many redirects (N)"` when a chain
      # exceeds `max_redirects`. Surface it as a normal `{:error, _}` (like
      # any other fetch failure) instead of letting it crash the caller.
      # Re-raise anything else so real bugs aren't swallowed.
      e in RuntimeError ->
        if e.message =~ "too many redirects" do
          {:error, %Error{reason: :too_many_redirects}}
        else
          reraise e, __STACKTRACE__
        end
    end
  end

  # GET/DELETE with an empty body: don't send one (matches HTTPoison).
  defp request_body(_method, body) when body in [nil, ""], do: nil
  defp request_body(_method, body), do: body

  defp put_receive_timeout(req_opts, opts) do
    case Keyword.get(opts, :recv_timeout) do
      nil -> req_opts
      ms -> Keyword.put(req_opts, :receive_timeout, ms)
    end
  end

  # HTTPoison `timeout:` is the connect timeout; `ssl:` are TLS transport
  # options. Both map onto Req's `connect_options`.
  defp put_connect_options(req_opts, opts) do
    connect =
      []
      |> maybe_put(:timeout, Keyword.get(opts, :timeout))
      |> maybe_put(:transport_opts, Keyword.get(opts, :ssl))

    if connect == [], do: req_opts, else: Keyword.put(req_opts, :connect_options, connect)
  end

  defp maybe_put(kw, _key, nil), do: kw
  defp maybe_put(kw, key, value), do: Keyword.put(kw, key, value)

  defp to_binary(body) when is_binary(body), do: body
  defp to_binary(nil), do: ""
  defp to_binary(body) when is_list(body), do: IO.iodata_to_binary(body)
  # With decode_body: false this shouldn't happen, but stay total.
  defp to_binary(body), do: body

  # Req: %{"content-type" => ["application/json"]} -> HTTPoison: [{"content-type", "application/json"}]
  defp to_header_list(headers) when is_map(headers) do
    Enum.flat_map(headers, fn {k, v} -> Enum.map(List.wrap(v), &{k, &1}) end)
  end

  defp to_header_list(headers) when is_list(headers), do: headers

  # Surface the underlying reason atom (:nxdomain, :timeout, :econnrefused)
  # so callers that pattern-match/log `reason` behave as they did with
  # HTTPoison; fall back to the exception itself otherwise.
  # Redirect-cap overflow: some Req versions return this struct, others
  # raise (handled by the rescue above). Normalise both to one clean atom.
  defp error_reason(%Req.TooManyRedirectsError{}), do: :too_many_redirects
  defp error_reason(%{reason: reason}), do: reason
  defp error_reason(exception), do: exception
end
