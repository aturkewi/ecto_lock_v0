defmodule EctoLock.Invoice do
  use Ecto.Schema

  import Ecto.Changeset, only: [ cast: 3 ]

  schema "invoices" do
    field(:pending, :boolean)
  end

  def changeset(%EctoLock.Invoice{} = invoice, attrs \\ %{}) do
    invoice
    |> cast(attrs, [:pending])
  end
end
