defmodule EctoLock.Invoice do
  use Ecto.Schema

  import Ecto.Changeset, only: [ cast: 3 ]
  import Ecto.Query, only: [from: 2]

  alias EctoLock.Invoice

  schema "invoices" do
    field(:pending, :boolean)
  end

  def pending(query \\ Invoice) do
    from(i in query,
      where: i.pending == true
    )
  end

  def changeset(%EctoLock.Invoice{} = invoice, attrs \\ %{}) do
    invoice
    |> cast(attrs, [:pending])
  end
end
