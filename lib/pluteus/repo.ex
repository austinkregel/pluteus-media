defmodule Pluteus.Repo do
  use Ecto.Repo,
    otp_app: :pluteus,
    adapter: Ecto.Adapters.Postgres
end
