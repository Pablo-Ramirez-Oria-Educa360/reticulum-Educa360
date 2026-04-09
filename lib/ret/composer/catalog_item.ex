defmodule Ret.Composer.CatalogItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ret.Account
  alias Ret.Composer.CatalogAsset

  @type t :: %__MODULE__{}

  @schema_prefix "ret0"
  @primary_key {:composer_catalog_item_id, :id, autogenerate: true}

  schema "composer_catalog_items" do
    field :part_key, :string
    field :name, :string
    field :category, :string
    field :subcategory, :string
    field :customizable, :boolean, default: false
    field :conflict_group, :string
    field :sort_order, :integer, default: 0

    belongs_to :model_asset, CatalogAsset, references: :composer_catalog_asset_id
    belongs_to :thumbnail_asset, CatalogAsset, references: :composer_catalog_asset_id
    belongs_to :created_by_account, Account, references: :account_id
    belongs_to :updated_by_account, Account, references: :account_id

    timestamps()
  end

  def changeset(
        %__MODULE__{} = item,
        %Account{} = actor,
        model_asset,
        thumbnail_asset,
        attrs
      ) do
    item
    |> cast(attrs, [
      :part_key,
      :name,
      :category,
      :subcategory,
      :customizable,
      :conflict_group,
      :sort_order
    ])
    |> maybe_generate_part_key()
    |> validate_required([:part_key, :name, :category])
    |> validate_length(:part_key, min: 1, max: 128)
    |> validate_length(:name, min: 1, max: 256)
    |> validate_length(:category, min: 1, max: 64)
    |> validate_format(:part_key, ~r/^[A-Za-z0-9_-]+$/)
    |> validate_inclusion(:category, categories())
    |> validate_asset_kind(:model_asset_id, model_asset, "model")
    |> validate_asset_kind(:thumbnail_asset_id, thumbnail_asset, "thumbnail")
    |> unique_constraint(:part_key)
    |> put_change(
      :model_asset_id,
      model_asset && model_asset.composer_catalog_asset_id
    )
    |> put_change(
      :thumbnail_asset_id,
      thumbnail_asset && thumbnail_asset.composer_catalog_asset_id
    )
    |> put_assoc(:updated_by_account, actor)
    |> maybe_put_created_by_account(actor)
  end

  defp maybe_put_created_by_account(%Ecto.Changeset{data: %__MODULE__{composer_catalog_item_id: nil}} = changeset, actor) do
    put_assoc(changeset, :created_by_account, actor)
  end

  defp maybe_put_created_by_account(changeset, _actor), do: changeset

  def categories do
    ~w(accessory beard body eyebrows eyes hair hands head mouth)
  end

  defp maybe_generate_part_key(changeset) do
    part_key = get_field(changeset, :part_key)

    if is_binary(part_key) and String.trim(part_key) != "" do
      changeset
    else
      base_part_key =
        [get_field(changeset, :category), slugify(get_field(changeset, :name))]
        |> Enum.filter(&(&1 not in [nil, ""]))
        |> Enum.join("_")

      generated_part_key =
        case base_part_key do
          "" -> "part_#{short_sid()}"
          base -> "#{base}_#{short_sid()}"
        end

      put_change(changeset, :part_key, generated_part_key)
    end
  end

  defp validate_asset_kind(changeset, _field, nil, _expected_kind), do: changeset

  defp validate_asset_kind(changeset, field, %CatalogAsset{kind: kind}, expected_kind) do
    if kind == expected_kind do
      changeset
    else
      add_error(changeset, field, "must reference a #{expected_kind} asset")
    end
  end

  defp slugify(nil), do: nil

  defp slugify(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
  end

  defp short_sid do
    Ret.Sids.generate_sid()
    |> String.replace("-", "")
    |> String.slice(0, 8)
  end
end
