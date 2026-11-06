defmodule HybridsocialWeb.Helpers.PostRateLimitResponse do
  @moduledoc "The 429 a client gets when `Social.PostRateLimit` refuses a post."
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def refuse(conn, %{window: window, limit: limit, retry_after: retry_after}) do
    conn
    |> put_resp_header("retry-after", Integer.to_string(retry_after))
    |> put_status(:too_many_requests)
    |> json(%{
      error: "limits.post_rate_limit",
      window: window,
      limit: limit,
      retry_after: retry_after
    })
  end
end
