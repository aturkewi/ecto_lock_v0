defmodule EctoLock.Repo do
  use Ecto.Repo,
    otp_app: :ecto_lock,
    adapter: Ecto.Adapters.Postgres
end
