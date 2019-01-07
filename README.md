Locking In Ecto

Why use locks?
We have an app that is in charge of sending out invoices when a set of criteria are met (X days before some date...). There is a task that we developed that checks daily for pending invoices that need to be sent. The issue that we found was that when we run this process in production we potentially run the risk of billing multiple times because we have multiple production servers and each one runs this task. Mo’ servers mo’ money right?

This is a great use case for database locks where we want to ensure that one process and only one process has access to a database row at a time.

Setting up a project
>If you don’t want to go through the setup of adding ecto and creating a migration, feel free to just clone _________ and use the pre-setup repo and then just skip down to ______________
Creating the database and connection

To start off with this, let’s set up the problem so we can play with this a bit.

```elixir
mix new --sup ecto_lock
```

Add ecto and postgres to your `mix.ex` file:

```elixir
defp deps do
    [
      {:ecto_sql, "~> 3.0"},
      {:postgrex, ">= 0.0.0"}
    ]
  end
```

And add the Ecto Repo to your application list (in the same file):

```elixir
def application do
    [
      mod: {EctoLock.Application, []},
      extra_applications: [:logger]
    ]
  end
```

And load the dependencies with `mix deps.get` in the terminal and create the db config with `mix ecto.gen.repo -r EctoLock.Repo`

Let’s also add our repo module to our startup processes by adding the following to our `lib/ecto_lock/application.ex`’s `start` function:

```
children = [
      EctoLock.Repo
    ]
```

And then replace `config/config.ex` file with:
```
use Mix.Config

config :ecto_lock, EctoLock.Repo,
  database: "ecto_lock_repo",
  hostname: "localhost"

config :ecto_lock, ecto_repos: [EctoLock.Repo]
```
Creating our Invoice table
To create the migration, let’s run `mix ecto.gen.migration create_invoices` in the terminal. Then replace `priv/repo/migrations/<some-numbers>_create_invoices.exs` with the following:

```elixir
defmodule EctoLock.Repo.Migrations.CreateInvoices do
  use Ecto.Migration

  def change do
    create table(:invoices) do
      add :pending, :boolean
    end
  end
end
```

This will create a very simple table that has one column, `pending`. In our app of course, the invoice table has many more columns with useful information (balance, due_date…), but we don’t need anything else to learn about lock :)

Finally, let's create a basic scheme file for an invoice at `lib/ecto_lock/invoice.ex` and fill it in with the following:

```elixir
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
```

Now this should be enough for us to get going!

Feeling the pain

Let’s write some code such that we actually run into this locking issue. Let’s create a new file at `lib/ecto_lock/bill_pending_invoices.ex` and fill it with the following:

```elixir
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

```

This just adds some basic functions that we can use to create, send, and update invoices. Let's give it a try!

Go ahead and start up the app by typing `iex -S mix` in the terminal . This will give us an interactive elixir process. After you run this, you should get the following:

```
Interactive Elixir (1.7.4) - press Ctrl+C to exit (type h() ENTER for help)
iex(1)>
```

Insides the elixir process, let's create a few pending invoices with:

```elixir
EctoLock.BillPendingInvoices.create_pending_invoice()
EctoLock.BillPendingInvoices.create_pending_invoice()
EctoLock.BillPendingInvoices.create_pending_invoice()
```

Then, let's send out the invoices by running the following in the Elixir process: `EctoLock.BillPendingInvoices.bill_pending_invoices()`. You should see something that looks like this:

```
iex(4)> EctoLock.BillPendingInvoices.bill_pending_invoices()

17:16:21.153 [debug] QUERY OK source="invoices" db=0.4ms queue=0.5ms
SELECT i0."id", i0."pending" FROM "invoices" AS i0 WHERE (i0."pending" = TRUE) []
Sending invoice 1...

17:16:21.159 [debug] QUERY OK source="invoices" db=0.9ms queue=0.5ms
SELECT i0."id", i0."pending" FROM "invoices" AS i0 WHERE (i0."id" = $1) [1]
Invoice 1 sent!

17:16:22.170 [debug] QUERY OK db=4.6ms queue=2.6ms
UPDATE "invoices" SET "pending" = $1 WHERE "id" = $2 [false, 1]
Sending invoice 2...

17:16:22.175 [debug] QUERY OK source="invoices" db=5.1ms
SELECT i0."id", i0."pending" FROM "invoices" AS i0 WHERE (i0."id" = $1) [2]
Invoice 2 sent!

17:16:23.184 [debug] QUERY OK db=4.4ms queue=2.8ms
UPDATE "invoices" SET "pending" = $1 WHERE "id" = $2 [false, 2]
Sending invoice 3...

17:16:23.190 [debug] QUERY OK source="invoices" db=5.0ms
SELECT i0."id", i0."pending" FROM "invoices" AS i0 WHERE (i0."id" = $1) [3]
Invoice 3 sent!

17:16:24.197 [debug] QUERY OK db=3.9ms queue=2.6ms
UPDATE "invoices" SET "pending" = $1 WHERE "id" = $2 [false, 3]
:ok
```

We can see that all three invoices were sent! Go ahead, run it again, you'll see there are no more invoices left to send and we'll get an immediate return (rather than the 3 second wait from 'hitting the api').

Now that all works well and good, but what if we had _two_ servers running this check at the same time? What would that look like? To simulate this, we're going to spin up two [elixir process](INSERT LINK HERE) that will run at relatively the same time.

>Note: Spawning an elixir process is just allowing some code to execute asynchronously. It's a great topic for another blog post, but for the moment, I think that should be enough of an understaning :)

Let's create a couple of helpers for ourselves here. Go ahead and create a file `lib/ecto_lock/helper.ex` and put the following in it:

```elixir
defmodule EctoLock.Helper do

  alias EctoLock.BillPendingInvoices

  def create_invoices do
    BillPendingInvoices.create_pending_invoice()
    BillPendingInvoices.create_pending_invoice()
    BillPendingInvoices.create_pending_invoice()
  end

  def bill_from_two_servers() do
    spawn(fn -> BillPendingInvoices.bill_pending_invoices() end)
    spawn(fn -> BillPendingInvoices.bill_pending_invoices() end)
  end
end
```

Here we've created a helper function to create some dummy data for us _and_ a function that will run our billing function twice at the same time.

Go ahead and resart your iex session (`ctrl + c` twice and then `iex -S mix`). Let's create some dummy data with `EctoLock.Helper.create_invoices()` and then let's run `EctoLock.Helper.bill_from_two_servers()`. This is what we get (note: I removed all of the sequal quries from below and only left our `IO.puts` to make this a bit more readable):

```
iex(2)> EctoLock.Helper.bill_from_two_servers()
Sending invoice 4...
Sending invoice 4...
Invoice 4 sent!
Invoice 4 sent!
Sending invoice 5...
Sending invoice 5...
Invoice 5 sent!
Invoice 5 sent!
Sending invoice 6...
Sending invoice 6...
Invoice 6 sent!
Invoice 6 sent!
```

Now that's a problem. We've sent out each invoice twice. 

Outline
  Introduction
    What were trying to do
    What was the problem
  Possible Solutions
    Only have one server run the process
    Locking
    Idempotence key
  Locking
    What does it do?
    How do you use it
      https://www.postgresql.org/docs/9.4/explicit-locking.html
      https://www.postgresql.org/docs/8.2/sql-lock.html
    Different types of locks
