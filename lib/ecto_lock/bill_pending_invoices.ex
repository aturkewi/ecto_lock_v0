defmodule EctoLock.BillPendingInvoices do
  alias EctoLock.{Invoice, Repo}

  def create_pending_invoice do
    %Invoice{}
    |> Invoice.changeset(%{pending: true})
    |> Repo.insert()
  end

  def bill_pending_invoices do
    Invoice.pending()
    |> Repo.all()
    |> Enum.each(fn invoice -> bill_pending_invoice(invoice.id) end)
  end

  def bill_pending_invoice(invoice_id) do
    invoice = get_invoice(invoice_id)
    bill_through_api(invoice)
    mark_invoice_sent(invoice)
  end

  def get_invoice(id) do
    Repo.get(Invoice, id)
  end

  def bill_through_api(invoice) do
    # let's assume it takes a second to hit the API
    IO.puts("Sending invoice #{invoice.id}...")
    :timer.sleep(1000)
    IO.puts("Invoice #{invoice.id} sent!")
  end

  def mark_invoice_sent(invoice) do
    invoice
    |> Invoice.changeset(%{pending: false})
    |> Repo.update()
  end
end
