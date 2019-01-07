defmodule EctoLock.BillPendingInvoices do
  alias EctoLock.{Invoice, Repo}

  def create_pending_invoice do
    %Invoice{}
    |> Invoice.changeset(%{pending: true})
    |> Repo.insert()
  end

  def bill_pending_invoice(invoice_id) do

  end

  def get_invoice(id) do

  end

  def bill_through_api(invoice) do

  end

  def update_invoice(invoice) do

  end
end
