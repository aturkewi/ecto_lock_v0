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
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_invoice, fn _ ->
      get_invoice(invoice_id)
    end)
    |> Ecto.Multi.run(:send_invoice, fn %{get_invoice: invoice} ->
      send_invoice(invoice)
    end)
    |> Repo.transaction()
  end

  def send_invoice(_invoice = nil), do: :ok

  def send_invoice(invoice) do
    bill_through_api(invoice)
    mark_invoice_sent(invoice)
  end

  def get_invoice(id) do
    try do
      Invoice
      |> Invoice.get_and_lock_invoice(id)
      |> Repo.one()
      |> return_invoice()
    rescue
      _e in Postgrex.Error -> {:error, "Could not obtain lock"}
    end
  end

  def return_invoice(invoice = %Invoice{}), do: {:ok, invoice}
  def return_invoice(_invoice = nil), do: {:error, "Could not find invoice"}

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
