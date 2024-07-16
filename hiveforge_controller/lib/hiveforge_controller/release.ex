defmodule HiveforgeController.Release do
  @app :hiveforge_controller

  def migrate do
    load_app()
    IO.puts("Migrating database")

    for repo <- repos() do
      IO.inspect(repo.config(), label: "Repo Config in migrate")

      ensure_all_started()
      start_repo(repo)

      IO.puts("Checking migrations in #{priv_path_for(repo, "migrations")}")
      migration_files = Path.wildcard(priv_path_for(repo, "migrations") <> "/*.exs")
      IO.inspect(migration_files, label: "Found migration files")

      case Ecto.Migrator.with_repo(repo, fn repo ->
        IO.puts("Running migrations for #{inspect(repo)}")
        migrations = Ecto.Migrator.migrations(repo)
        IO.inspect(migrations, label: "Migrations available before run")
        result = Ecto.Migrator.run(repo, :up, all: true)
        IO.inspect(result, label: "Migrations result")
        result
      end) do
        {:ok, versions, _} ->
          IO.puts("Migration completed for #{inspect(repo)}")
          IO.puts("Applied versions: #{inspect(versions)}")
        {:error, reason} ->
          IO.puts("Migration failed for #{inspect(repo)}: #{inspect(reason)}")
          exit(1)
      end
    end
  end

  def create_db do
    load_app()
    IO.puts("Creating database")

    for repo <- repos() do
      IO.inspect(repo.config(), label: "Repo Config in create_db")
      ensure_all_started()
      case ensure_repo_created(repo) do
        :ok -> IO.puts("Database created for #{inspect(repo)}")
        {:error, reason} ->
          IO.puts("Database creation failed for #{inspect(repo)}: #{inspect(reason)}")
          exit(1)
      end
    end
  end

  defp start_repo(repo) do
    case repo.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> raise "Failed to start repo #{inspect(repo)}: #{inspect(reason)}"
    end
  end

  defp ensure_repo_created(repo) do
    IO.inspect(repo.config(), label: "Repo Config in ensure_repo_created")

    case repo.__adapter__().storage_up(repo.config()) do
      :ok -> :ok
      {:error, :already_up} -> :ok
      {:error, term} -> {:error, term}
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    IO.puts("Loading application")
    Application.load(@app)
  end

  defp ensure_all_started do
    IO.puts("Starting all necessary applications")
    Application.ensure_all_started(:telemetry)
    {:ok, _} = Application.ensure_all_started(@app)
  end

  defp priv_path_for(repo, filename) do
    app = Keyword.fetch!(repo.config(), :otp_app)
    repo_underscore = repo |> Module.split() |> List.last() |> Macro.underscore()
    Path.join([:code.priv_dir(app), repo_underscore, filename])
  end
end
