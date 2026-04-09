defmodule RetWeb.Api.V1.ComposerCatalogController do
  use RetWeb, :controller

  alias Ret.Composer.{Catalog, CatalogAsset}
  alias Ret.Repo
  alias RetWeb.ControllerHelpers

  def index(conn, _params) do
    conn |> json(Catalog.catalog_response())
  end

  def capabilities(conn, _params) do
    account = Guardian.Plug.current_resource(conn)
    conn |> json(Catalog.capabilities(account))
  end

  def create_asset(conn, %{"asset" => params}) do
    account = Guardian.Plug.current_resource(conn)

    with {:ok, owned_file} <-
           Ret.Storage.promote(
             params["file_id"],
             params["access_token"],
             params["promotion_token"],
             account,
             false
           ),
         {:ok, asset} <- Catalog.create_asset(account, owned_file, params) do
      conn
      |> json(%{
        asset: %{
          id: asset.catalog_asset_sid,
          kind: asset.kind,
          name: asset.name,
          url: Ret.OwnedFile.url_or_nil_for(owned_file),
          content_type: owned_file.content_type,
          content_length: owned_file.content_length
        }
      })
    else
      {:error, %Ecto.Changeset{} = changeset} -> ControllerHelpers.render_error_json(conn, changeset)
      {:error, :not_found} -> ControllerHelpers.render_error_json(conn, :not_found)
      {:error, :not_allowed} -> ControllerHelpers.render_error_json(conn, :unauthorized)
      {:error, error} -> ControllerHelpers.render_error_json(conn, error)
    end
  end

  def create_item(conn, %{"item" => params}) do
    account = Guardian.Plug.current_resource(conn)

    with {:ok, model_asset} <- fetch_optional_asset(params["model_asset_id"]),
         {:ok, thumbnail_asset} <- fetch_optional_asset(params["thumbnail_asset_id"]),
         {:ok, item} <- Catalog.create_item(account, model_asset, thumbnail_asset, normalize_item_params(params)) do
      created_item = item.part_key |> Catalog.item_by_part_key() |> Catalog.serialize_item()
      conn |> json(%{item: created_item})
    else
      {:error, :asset_not_found} -> ControllerHelpers.render_error_json(conn, :not_found)
      {:error, %Ecto.Changeset{} = changeset} -> ControllerHelpers.render_error_json(conn, changeset)
      {:error, error} -> ControllerHelpers.render_error_json(conn, error)
    end
  end

  def delete_item(conn, %{"id" => part_key}) do
    case Catalog.item_by_part_key(part_key) do
      nil ->
        ControllerHelpers.render_error_json(conn, :not_found)

      item ->
        case Catalog.delete_item(item) do
          {:ok, :ok} -> conn |> json(%{status: "ok"})
          {:error, %Ecto.Changeset{} = changeset} -> ControllerHelpers.render_error_json(conn, changeset)
          {:error, error} -> ControllerHelpers.render_error_json(conn, error)
        end
    end
  end

  defp normalize_item_params(params) do
    normalized =
      params
    |> Map.take([
      "id",
      "name",
      "category",
      "subCategory",
      "customizable",
      "conflictGroup",
      "sortOrder"
    ])
    |> Enum.reduce(%{}, fn
      {"id", value}, acc -> Map.put(acc, :part_key, value)
      {"subCategory", value}, acc -> Map.put(acc, :subcategory, value)
      {"conflictGroup", value}, acc -> Map.put(acc, :conflict_group, value)
      {"sortOrder", value}, acc -> Map.put(acc, :sort_order, value)
      {key, value}, acc -> Map.put(acc, String.to_existing_atom(key), value)
    end)

    normalized
  end

  defp fetch_optional_asset(nil), do: {:ok, nil}
  defp fetch_optional_asset(""), do: {:ok, nil}

  defp fetch_optional_asset(id) when is_binary(id) do
    case Repo.get_by(CatalogAsset, catalog_asset_sid: id) do
      nil -> {:error, :asset_not_found}
      asset -> {:ok, asset}
    end
  end
end
