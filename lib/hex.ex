defmodule Hex do
  use Application

  def start do
    {:ok, _} = Application.ensure_all_started(:hex)
  end

  def stop do
    case Application.stop(:hex) do
      :ok -> :ok
      {:error, {:not_started, :hex}} -> :ok
    end
  end

  def start(_, _) do
    import Supervisor.Spec

    Mix.SCM.append(Hex.SCM)
    Mix.RemoteConverger.register(Hex.RemoteConverger)

    Hex.Version.start
    start_httpc()

    children = [
      worker(Hex.State, []),
      worker(Hex.Registry.ETS, []),
      worker(Hex.Parallel, [:hex_fetcher, [max_parallel: 64]]),
    ]

    opts = [strategy: :one_for_one, name: Hex.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def version,        do: unquote(Mix.Project.config[:version])
  def elixir_version, do: unquote(System.version)
  def otp_version,    do: unquote(Hex.Utils.otp_version)

  @spec config_snippet(String.t) :: {:ok, String.t} | {:error, atom}
  def config_snippet(package) do
    Hex.start
    Hex.Utils.ensure_registry(cache: false)

    case Hex.API.Package.get(package) do
      {404, _, _} ->
        {:error, :no_package}
      {code, body, _} when code in 200..299 ->
        case body["releases"] do
          [release|_] ->
            snippet = Hex.Utils.format_release_config(package, release)
            {:ok, snippet}
          [] ->
            {:error, :no_releases}
        end
      _ ->
        {:error, :unknown}
    end
  end

  defp start_httpc() do
    :inets.start(:httpc, profile: :hex)
    opts = [
      max_sessions: 8,
      max_keep_alive_length: 4,
      keep_alive_timeout: 120_000
    ]
    :httpc.set_options(opts, :hex)
  end
end
