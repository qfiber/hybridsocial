defmodule HybridsocialWeb.Api.V1.FundingController do
  use HybridsocialWeb, :controller
  import Ecto.Query

  def index(conn, _params) do
    methods =
      try do
        Hybridsocial.Premium.Funding
        |> where([f], f.enabled == true)
        |> Hybridsocial.Repo.all()
        |> Enum.map(fn f ->
          %{
            id: f.id,
            platform: f.platform,
            display_text: f.display_text,
            goal_amount: f.goal_amount,
            current_amount: f.current_amount
          }
        end)
      rescue
        _ -> []
      end

    json(conn, methods)
  end
end
