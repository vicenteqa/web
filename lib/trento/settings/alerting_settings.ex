defmodule Trento.Settings.AlertingSettings do
  @moduledoc """
  Schema and functions related to alerting settings.
  """

  use Ecto.Schema
  use Trento.Support.Ecto.STI, sti_identifier: :alerting_settings

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @cast_fields ~w(enabled sender_email recipient_email smtp_server smtp_port smtp_username smtp_password)a

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "settings" do
    field :enabled, :boolean, source: :alerting_enabled
    field :sender_email, :string, source: :alerting_sender_email
    field :recipient_email, :string, source: :alerting_recipient_email
    field :smtp_server, :string, source: :alerting_smtp_server
    field :smtp_port, :integer, source: :alerting_smtp_port
    field :smtp_username, :string, source: :alerting_smtp_username

    field :smtp_password, Trento.Support.Ecto.EncryptedBinary,
      source: :alerting_smtp_password,
      redact: true

    field :enforced_from_env, :boolean, virtual: true, default: false
    timestamps(type: :utc_datetime_usec)
    sti_fields()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(alerting_settings, changes) do
    alerting_settings
    |> cast(changes, @cast_fields)
    |> sti_changes()
    |> validate_required(@cast_fields)
    |> validate_format(:sender_email, ~r/@/, message: "Invalid e-mail address.")
    |> validate_format(:recipient_email, ~r/@/, message: "Invalid e-mail address.")
    |> validate_number(:smtp_port,
      greater_than: 0,
      less_than_or_equal_to: 65_535,
      message: "Invalid port number."
    )
    |> unique_constraint(:type)
  end
end
