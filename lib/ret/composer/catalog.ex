defmodule Ret.Composer.Catalog do
  require Logger
  import Ecto.Query

  alias Ret.{Account, OwnedFile, Repo, Storage}
  alias Ret.Composer.{CatalogAsset, CatalogItem}

  @preloads [
    model_asset: [:owned_file],
    thumbnail_asset: [:owned_file]
  ]

  def list_items do
    CatalogItem
    |> order_by([item], asc: item.sort_order, asc: item.name)
    |> preload(^@preloads)
    |> Repo.all()
  end

  def catalog_response do
    %{
      "AVATAR_PARTS" => Enum.map(list_items(), &serialize_item/1),
      "OVERLAYS" => %{},
      "UI_ICONS" => %{}
    }
  end

  def capabilities(nil), do: %{"can_manage_catalog" => false}
  def capabilities(%Account{is_admin: true}), do: %{"can_manage_catalog" => true}
  def capabilities(%Account{}), do: %{"can_manage_catalog" => false}

  def create_asset(%Account{} = account, %Ret.OwnedFile{} = owned_file, attrs) do
    %CatalogAsset{}
    |> CatalogAsset.changeset(account, owned_file, attrs)
    |> Repo.insert()
  end

  def create_item(
        %Account{} = account,
        model_asset,
        thumbnail_asset,
        attrs
      ) do
    %CatalogItem{}
    |> CatalogItem.changeset(account, model_asset, thumbnail_asset, attrs)
    |> Repo.insert()
  end

  def item_by_part_key(part_key) when is_binary(part_key) do
    CatalogItem
    |> Repo.get_by(part_key: part_key)
    |> maybe_preload_item()
  end

  def delete_item(%CatalogItem{} = item) do
    item = maybe_preload_item(item)

    with {:ok, owned_files_to_remove} <- delete_item_records(item) do
      Enum.each(owned_files_to_remove, &safe_remove_owned_file_blobs/1)
      {:ok, :ok}
    end
  end

  def serialize_item(%CatalogItem{} = item) do
    %{
      "id" => item.part_key,
      "name" => item.name,
      "url" => serialize_owned_file_url(item.model_asset),
      "thumbnail" => serialize_owned_file_url(item.thumbnail_asset),
      "category" => item.category,
      "subCategory" => item.subcategory,
      "customizable" => item.customizable,
      "conflictGroup" => item.conflict_group
    }
  end

  defp serialize_owned_file_url(%CatalogAsset{owned_file: owned_file}),
    do: OwnedFile.url_or_nil_for(owned_file)

  defp serialize_owned_file_url(_), do: nil

  defp maybe_preload_item(nil), do: nil
  defp maybe_preload_item(item), do: Repo.preload(item, @preloads)

  defp delete_item_records(%CatalogItem{} = item) do
    Repo.transaction(fn ->
      with {:ok, _item} <- Repo.delete(item),
           {:ok, model_owned_file} <- delete_unused_asset(item.model_asset),
           {:ok, thumbnail_owned_file} <- delete_unused_asset(item.thumbnail_asset) do
        [model_owned_file, thumbnail_owned_file]
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq_by(& &1.owned_file_id)
      else
        {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback(changeset)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp delete_unused_asset(nil), do: {:ok, nil}

  defp delete_unused_asset(%CatalogAsset{} = asset) do
    if asset_still_referenced?(asset.composer_catalog_asset_id) do
      {:ok, nil}
    else
      owned_file = asset.owned_file

      with {:ok, _asset} <- Repo.delete(asset),
           {:ok, deleted_owned_file} <- maybe_delete_owned_file(owned_file) do
        {:ok, deleted_owned_file}
      end
    end
  end

  defp asset_still_referenced?(asset_id) do
    CatalogItem
    |> where(
      [item],
      item.model_asset_id == ^asset_id or item.thumbnail_asset_id == ^asset_id
    )
    |> Repo.exists?()
  end

  defp maybe_delete_owned_file(nil), do: {:ok, nil}

  defp maybe_delete_owned_file(%OwnedFile{} = owned_file) do
    if owned_file_still_referenced?(owned_file.owned_file_id) do
      {:ok, nil}
    else
      case Repo.delete(owned_file) do
        {:ok, deleted_owned_file} -> {:ok, deleted_owned_file}
        {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      end
    end
  end

  defp owned_file_still_referenced?(owned_file_id) do
    CatalogAsset
    |> where([asset], asset.owned_file_id == ^owned_file_id)
    |> Repo.exists?()
  end

  defp safe_remove_owned_file_blobs(%OwnedFile{} = owned_file) do
    Storage.rm_files_for_owned_file(owned_file)
  rescue
    error in File.Error ->
      Logger.warning(
        "failed to remove composer catalog owned file blobs for #{owned_file.owned_file_uuid}: #{Exception.message(error)}"
      )

      :ok
  end
end
