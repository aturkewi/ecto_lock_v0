defmodule EctoLock.Repo.Migrations.CreateInvoices do
  use Ecto.Migration

  def change do
    create table(:invoices) do
      add :pending, :boolean
    end
  end
end
