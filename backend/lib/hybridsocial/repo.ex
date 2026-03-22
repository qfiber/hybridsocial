defmodule Hybridsocial.Repo do
  use Ecto.Repo,
    otp_app: :hybridsocial,
    adapter: Ecto.Adapters.Postgres
end
