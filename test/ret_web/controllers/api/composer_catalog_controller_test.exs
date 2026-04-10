defmodule RetWeb.ComposerCatalogControllerTest do
  use RetWeb.ConnCase
  import Ret.TestHelpers

  alias Ret.Composer.CatalogAsset
  alias Ret.Repo

  setup [:create_account]

  test "catalog index returns empty contract when there are no items", %{conn: conn} do
    response = conn |> get(api_v1_composer_catalog_path(conn, :index)) |> json_response(200)

    assert response == %{
             "AVATAR_PARTS" => [],
             "OVERLAYS" => %{},
             "UI_ICONS" => %{}
           }
  end

  test "catalog index serializes active items in composer format", %{conn: conn, account: account} do
    %{item: item} = create_composer_catalog_item(account)

    response = conn |> get(api_v1_composer_catalog_path(conn, :index)) |> json_response(200)

    assert [
             %{
               "id" => item.part_key,
               "name" => "Test Composer Item",
               "category" => "accessory",
               "subCategory" => "hat",
               "customizable" => true,
               "conflictGroup" => "headwear",
               "thumbnail" => thumbnail_url,
               "url" => model_url
             }
           ] = response["AVATAR_PARTS"]

    assert is_binary(model_url)
    assert is_binary(thumbnail_url)
    assert response["OVERLAYS"] == %{}
    assert response["UI_ICONS"] == %{}
  end

  test "catalog capabilities returns false without authentication", %{conn: conn} do
    response =
      conn
      |> get(api_v1_composer_catalog_path(conn, :capabilities))
      |> json_response(200)

    assert response == %{"can_manage_catalog" => false}
  end

  test "catalog capabilities returns true for admin users", %{conn: conn} do
    admin_account = create_account("composer-admin", true)

    response =
      conn
      |> put_auth_header_for_account(admin_account)
      |> get(api_v1_composer_catalog_path(conn, :capabilities))
      |> json_response(200)

    assert response == %{"can_manage_catalog" => true}
  end

  test "admin can create catalog assets and items, including items without model or thumbnail", %{conn: conn} do
    admin_account = create_account("composer-admin-create", true)
    model_owned_file = create_composer_model_owned_file(admin_account)

    model_asset_response =
      conn
      |> put_auth_header_for_account(admin_account)
      |> post(api_v1_composer_catalog_path(conn, :create_asset), %{
        asset: %{
          name: "Uploaded Model",
          kind: "model",
          file_id: model_owned_file.owned_file_uuid,
          access_token: model_owned_file.key
        }
      })
      |> json_response(200)

    assert model_asset_response["asset"]["kind"] == "model"
    assert is_binary(model_asset_response["asset"]["id"])

    item_response =
      conn
      |> put_auth_header_for_account(admin_account)
      |> post(api_v1_composer_catalog_path(conn, :create_item), %{
        item: %{
          id: "hair_none",
          name: "Nada",
          category: "hair",
          customizable: false
        }
      })
      |> json_response(200)

    assert item_response["item"]["id"] == "hair_none"
    assert item_response["item"]["url"] == nil
    assert item_response["item"]["thumbnail"] == nil
  end

  test "admin can update catalog items, keep existing files, and replace uploaded assets", %{conn: conn, account: account} do
    admin_account = create_account("composer-admin-update", true)
    %{item: item} = create_composer_catalog_item(account, %{part_key: "editable_hat"})
    original_thumbnail_asset_id = item.thumbnail_asset.composer_catalog_asset_id
    original_thumbnail_url = item.thumbnail_asset.owned_file |> Ret.OwnedFile.url_or_nil_for()
    expected_model_url = item.model_asset.owned_file |> Ret.OwnedFile.url_or_nil_for()

    replacement_thumbnail_owned_file = create_composer_thumbnail_owned_file(admin_account)

    replacement_thumbnail_asset =
      create_composer_catalog_asset(
        admin_account,
        "thumbnail",
        replacement_thumbnail_owned_file,
        "Replacement Thumbnail"
      )

    response =
      conn
      |> put_auth_header_for_account(admin_account)
      |> patch(api_v1_composer_catalog_path(conn, :update_item, item.part_key), %{
        item: %{
          name: "Updated Hat",
          category: "head",
          customizable: false,
          thumbnail_asset_id: replacement_thumbnail_asset.catalog_asset_sid
        }
      })
      |> json_response(200)

    assert response["item"]["id"] == "editable_hat"
    assert response["item"]["name"] == "Updated Hat"
    assert response["item"]["category"] == "head"
    assert response["item"]["url"] == expected_model_url
    assert response["item"]["thumbnail"] != original_thumbnail_url
    assert response["item"]["conflictGroup"] == nil

    refute Repo.get(CatalogAsset, original_thumbnail_asset_id)
  end

  test "admin can hard delete catalog items and they disappear from catalog", %{conn: conn, account: account} do
    admin_account = create_account("composer-admin-delete", true)
    %{item: item} = create_composer_catalog_item(account, %{part_key: "deletable_hat"})

    conn
    |> put_auth_header_for_account(admin_account)
    |> delete(api_v1_composer_catalog_path(conn, :delete_item, item.part_key))
    |> json_response(200)

    response = conn |> get(api_v1_composer_catalog_path(conn, :index)) |> json_response(200)

    refute Enum.any?(response["AVATAR_PARTS"], &(&1["id"] == "deletable_hat"))
  end

  test "admin cannot create items with unsupported categories", %{conn: conn} do
    admin_account = create_account("composer-admin-invalid-category", true)

    response =
      conn
      |> put_auth_header_for_account(admin_account)
      |> post(api_v1_composer_catalog_path(conn, :create_item), %{
        item: %{
          name: "Broken Item",
          category: "cape"
        }
      })
      |> json_response(422)

    assert response["errors"]["category"] != []
  end

  test "admin cannot assign thumbnail assets as models", %{conn: conn} do
    admin_account = create_account("composer-admin-invalid-asset-kind", true)
    thumbnail_owned_file = create_composer_thumbnail_owned_file(admin_account)

    thumbnail_asset =
      create_composer_catalog_asset(
        admin_account,
        "thumbnail",
        thumbnail_owned_file,
        "Wrong Asset"
      )

    response =
      conn
      |> put_auth_header_for_account(admin_account)
      |> post(api_v1_composer_catalog_path(conn, :create_item), %{
        item: %{
          name: "Broken Item",
          category: "hair",
          model_asset_id: thumbnail_asset.catalog_asset_sid
        }
      })
      |> json_response(422)

    assert response["errors"]["model_asset_id"] != []
  end
end
