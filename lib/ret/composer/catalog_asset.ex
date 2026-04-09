defmodule Ret.Composer.CatalogAsset do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ret.{Account, OwnedFile}

  @type t :: %__MODULE__{}

  @schema_prefix "ret0"
  @primary_key {:composer_catalog_asset_id, :id, autogenerate: true}

  schema "composer_catalog_assets" do
    field :catalog_asset_sid, :string
    field :name, :string
    field :kind, :string

    belongs_to :owned_file, OwnedFile, references: :owned_file_id
    belongs_to :created_by_account, Account, references: :account_id

    timestamps()
  end

  @asset_kinds ~w(model thumbnail)

  def changeset(%__MODULE__{} = asset, %Account{} = account, %OwnedFile{} = owned_file, attrs) do
    asset
    |> cast(attrs, [:catalog_asset_sid, :name, :kind])
    |> validate_required([:name, :kind])
    |> validate_length(:name, min: 1, max: 256)
    |> validate_inclusion(:kind, @asset_kinds)
    |> validate_owned_file_type(owned_file)
    |> maybe_add_catalog_asset_sid()
    |> unique_constraint(:catalog_asset_sid)
    |> put_assoc(:owned_file, owned_file)
    |> put_assoc(:created_by_account, account)
  end

  defp maybe_add_catalog_asset_sid(changeset) do
    catalog_asset_sid = get_field(changeset, :catalog_asset_sid) || Ret.Sids.generate_sid()
    put_change(changeset, :catalog_asset_sid, catalog_asset_sid)
  end

  defp validate_owned_file_type(changeset, %OwnedFile{content_type: content_type}) do
    kind = get_field(changeset, :kind)

    valid? =
      case kind do
        "model" -> valid_model_content_type?(content_type)
        "thumbnail" -> valid_thumbnail_content_type?(content_type)
        _ -> true
      end

    if valid? do
      changeset
    else
      add_error(changeset, :kind, "does not match the uploaded file type")
    end
  end

  defp valid_model_content_type?(content_type) when is_binary(content_type) do
    String.starts_with?(content_type, "model/") or
      content_type in ["application/octet-stream", "application/gltf-buffer"]
  end

  defp valid_model_content_type?(_), do: false

  defp valid_thumbnail_content_type?(content_type) when is_binary(content_type),
    do: String.starts_with?(content_type, "image/")

  defp valid_thumbnail_content_type?(_), do: false
end
