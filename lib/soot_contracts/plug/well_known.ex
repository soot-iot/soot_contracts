defmodule SootContracts.Plug.WellKnown do
  @moduledoc """
  Serves the contract bundle at:

      GET /.well-known/soot/contract
        → 200 application/json — the manifest of the current bundle.

      GET /.well-known/soot/contract/:fingerprint
        → 200 application/json — the manifest of that specific bundle.

      GET /.well-known/soot/contract/:fingerprint/<asset-path>
        → 200 with the asset bytes; content-type per filename.

  In production mount this **behind** `AshPki.Plug.MTLS` so only
  authenticated devices can fetch contracts. The plug itself doesn't
  enforce authentication; the mTLS layer does.

  ETag is the manifest fingerprint; matching `If-None-Match` returns
  `304`. Unknown fingerprints yield `404`. Unknown asset paths yield
  `404`.
  """

  @behaviour Plug
  import Plug.Conn

  alias SootContracts.{BundleRow, CanonicalJSON, Publisher}

  @manifest_prefix "/.well-known/soot/contract"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: "GET"} = conn, _opts) do
    case route(conn) do
      :current_manifest -> serve_current(conn)
      {:manifest, fp} -> serve_manifest(conn, fp)
      {:asset, fp, path} -> serve_asset(conn, fp, path)
      :not_matched -> not_found(conn, "no_route")
    end
  end

  def call(conn, _opts), do: send_json(conn, 405, %{error: "method_not_allowed"})

  # ─── routing ──────────────────────────────────────────────────────────

  defp route(conn) do
    path = "/" <> Enum.join(conn.path_info, "/")
    do_route(path)
  end

  defp do_route(@manifest_prefix), do: :current_manifest
  defp do_route(@manifest_prefix <> "/"), do: :current_manifest

  defp do_route(@manifest_prefix <> "/" <> rest) do
    case String.split(rest, "/", parts: 2) do
      [fp] when fp != "" ->
        {:manifest, fp}

      [fp, path] when fp != "" and path != "" ->
        {:asset, fp, path}

      _ ->
        :not_matched
    end
  end

  defp do_route(_), do: :not_matched

  # ─── handlers ─────────────────────────────────────────────────────────

  defp serve_current(conn) do
    case Publisher.current() do
      nil -> not_found(conn, "no_current_bundle")
      row -> serve_manifest_row(conn, row)
    end
  end

  defp serve_manifest(conn, fingerprint) do
    case fetch_servable(fingerprint) do
      {:ok, row} -> serve_manifest_row(conn, row)
      :error -> not_found(conn, "unknown_fingerprint")
    end
  end

  defp serve_asset(conn, fingerprint, path) do
    case fetch_servable(fingerprint) do
      {:ok, %BundleRow{assets: assets}} ->
        case Map.get(assets, path) do
          nil -> not_found(conn, "unknown_asset")
          body -> send_asset(conn, fingerprint, path, body)
        end

      :error ->
        not_found(conn, "unknown_fingerprint")
    end
  end

  defp fetch_servable(fingerprint) do
    case BundleRow.get_by_fingerprint(fingerprint, authorize?: false) do
      {:ok, %BundleRow{status: :retired}} -> :error
      {:ok, %BundleRow{} = row} -> {:ok, row}
      {:error, _} -> :error
    end
  end

  defp serve_manifest_row(conn, %BundleRow{manifest: manifest, fingerprint: fp}) do
    if etag_matches?(conn, fp) do
      conn |> put_resp_header("etag", quote_etag(fp)) |> send_resp(304, "") |> halt()
    else
      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("etag", quote_etag(fp))
      |> put_resp_header("cache-control", "no-cache")
      |> send_resp(200, CanonicalJSON.encode_pretty!(manifest))
      |> halt()
    end
  end

  defp send_asset(conn, fingerprint, path, body) do
    if etag_matches?(conn, fingerprint <> ":" <> path) do
      conn
      |> put_resp_header("etag", quote_etag(fingerprint <> ":" <> path))
      |> send_resp(304, "")
      |> halt()
    else
      conn
      |> put_resp_content_type(content_type_for(path))
      |> put_resp_header("etag", quote_etag(fingerprint <> ":" <> path))
      |> put_resp_header("cache-control", "public, max-age=86400, immutable")
      |> send_resp(200, body)
      |> halt()
    end
  end

  defp not_found(conn, code), do: send_json(conn, 404, %{error: code})

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
    |> halt()
  end

  defp etag_matches?(conn, value) do
    quoted = quote_etag(value)

    Plug.Conn.get_req_header(conn, "if-none-match")
    |> Enum.any?(&(&1 == quoted or &1 == value))
  end

  defp quote_etag(value), do: ~s("#{value}")

  defp content_type_for(path) do
    cond do
      String.ends_with?(path, ".json") -> "application/json"
      String.ends_with?(path, ".pem") -> "application/x-pem-file"
      String.ends_with?(path, ".txt") -> "text/plain"
      String.ends_with?(path, ".arrow_schema") -> "application/json"
      true -> "application/octet-stream"
    end
  end
end
