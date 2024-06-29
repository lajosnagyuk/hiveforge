defmodule HiveforgeController.Repo do
  use Ecto.Repo,
    otp_app: :hiveforge_controller,
    adapter: Ecto.Adapters.Postgres
end
