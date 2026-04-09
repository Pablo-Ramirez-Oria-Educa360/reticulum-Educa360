defmodule Ret.Repo.Migrations.CreateComposerCatalogTables do
  use Ecto.Migration

  def change do
    create table(:composer_catalog_assets, primary_key: false) do
      add :composer_catalog_asset_id, :bigint,
        default: fragment("ret0.next_id()"),
        primary_key: true

      add :catalog_asset_sid, :string, null: false
      add :name, :string, null: false
      add :kind, :string, null: false

      add :owned_file_id,
          references(:owned_files, column: :owned_file_id, on_delete: :delete_all),
          null: false

      add :created_by_account_id,
          references(:accounts, column: :account_id, on_delete: :nothing),
          null: false

      timestamps()
    end

    create unique_index(:composer_catalog_assets, [:catalog_asset_sid])
    create index(:composer_catalog_assets, [:kind])
    create index(:composer_catalog_assets, [:owned_file_id])
    create index(:composer_catalog_assets, [:created_by_account_id])

    create table(:composer_catalog_items, primary_key: false) do
      add :composer_catalog_item_id, :bigint,
        default: fragment("ret0.next_id()"),
        primary_key: true

      add :part_key, :string, null: false
      add :name, :string, null: false
      add :category, :string, null: false
      add :subcategory, :string
      add :customizable, :boolean, default: false, null: false
      add :conflict_group, :string
      add :sort_order, :integer, default: 0, null: false

      add :model_asset_id,
          references(:composer_catalog_assets,
            column: :composer_catalog_asset_id,
            on_delete: :restrict
          )

      add :thumbnail_asset_id,
          references(:composer_catalog_assets,
            column: :composer_catalog_asset_id,
            on_delete: :restrict
          )

      add :created_by_account_id,
          references(:accounts, column: :account_id, on_delete: :nothing),
          null: false

      add :updated_by_account_id,
          references(:accounts, column: :account_id, on_delete: :nothing),
          null: false

      timestamps()
    end

    create unique_index(:composer_catalog_items, [:part_key])
    create index(:composer_catalog_items, [:category, :sort_order])
  end
end
