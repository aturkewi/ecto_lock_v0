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

This just adds some basic functions that we can use to create, send, and update invoices. We want to grab all of our pending invoices with `bill_pending_invoices` and then send each one. For each one we send, we need to get the invoice, hit our billing API, and then update our own database so that we know that invoice was sent. For the purposes of this blog paste, we're just adding a one second delay (`:timer.sleep(1000)`) where we are pretending that is the API request/response. Now, let's give it a try!

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

>Note: Spawning an elixir process is just allowing some code to execute asynchronously. It's a great topic for another blog post, but for the moment, I think that should be enough of an understanding :)

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

Possible Solutions

There are of course many possible solutions to this problem. I'll touch on a few of the ones we considered, but I won't go too deep into any of them.

Only Run the Process On One Server

This was my first thought when we ran into this issue. I figured that easiest solution would be to just _avoid_ this problem in the first place. After talking with the team though, we realized that:

1. There are much larger operation concerns here with regards to how to do this. Is one server designated prime? What if it goes down? Do all the servers need to then talk to eachother...

and

2. When dealing with something like invoicing users, we want to be _sure_ that we're not billing them twice or anything like that. Rather than relying on the right number of the right servers being in rotation, we want to use a more robust industry standard tool (locking...?)

Idempotence Keys (Stripe Specific)

This idea had more to do with Strip specifically. The idea was that if we tagged each invoice we sent with an idempotence key, Stripe would know not to duplicate an invoice on their end. The short answer here is that this does not work how we originally thought it might. That tool is used to just return the exact same response if the same request is sent twice. So what would happen if our first request to Stripe failed? Then any time we would retry the request we'd get the same failed response again and again :( Also, accoriding to the Stripe docs, this key is _not_ meant to be used to ensure that double billing does not take place.

Locking

The idea here is that each server looks up an invoice to send it. When it retrieves the invoice from the database, it puts a _lock_ on that row so that _no other process can access it_. This would mean that if Server A looked up invoice 7 and got a lock on it, Server B would not be able to retrieve the invoice and therefore would _not_ be able to send it out.

Locking

What does it do?

Surprise surprise, we ended up going with database locking! Database locking is a very robust and well used tool. It's been a feature of SQL databases since YYYY.

As explained above, database locking allows us to make a row in accessible. We can use this tool to ensure that only one process is working on a pieces of data at a time so we can avoid write conflicts (two processes try and make updates at the same time).

How do you use it?

Let's go over how we can use [Ecto's lock function](link to ecto lock). To do this, we're going to also want to use [`Ecto.Multi`](https://hexdocs.pm/ecto/Ecto.Multi.html). I don't want to go too far into how this tool works, but it basically allows us to write a database transaction (meaning all the steps happen, or none of them do). We are using this so that we can lock our row for the duration of a transaction.

Like all Ecto queries, there are two ways we can use this. We can either use the keyword syntax, or the expression syntax. I'm going to go ahead and use the keyword syntax, but either would work.  

First, let's add the following function to our `Invoice` module:

```elixir
def get_and_lock_invoice(query \\ Invoice, invoice_id) do
  from(i in query,
    where: i.id == ^invoice_id,
    lock: "FOR UPDATE"
  )
end
```

Here we are querying for an invoice and then locking it. The string that we're passing to lock has to be a very specific string though. We can take a look at some options for postgres [here](https://www.postgresql.org/docs/9.4/explicit-locking.html). See the section on `FOR UPDATE`. This ensures that this row is locked _until we update it_ in this transaction. We are also adding the `NOWAIT` option to ensure that other process will simply fail when trying to retrieve this same row rather than _waiting_ to perform their action. If you leave the `NOWAIT` option off, then out second process would still try and send out an invoice after the first completes (though we _could_ have it check to see if the invoice was already sent, but it would mean that we're forcing a process to sit and wait when we know there won't be any more work for it to do on a given invoice).

Now let's update our `get_invoice` function in the `EctoLock.BillPendingInvoices` module to look like:

```elixir
def get_invoice(id) do
  Invoice
  |> Invoice.get_and_lock_invoice(id)
  |> Repo.one()
end
```

This will now ensure that when we retrieve the invoice, we are also locking it. Let's go ahead an test our code again to see how it works! Go ahead and start up your elixir terminal and run the following commands:

```elixir
EctoLock.Helper.create_invoices()
EctoLock.Helper.bill_from_two_servers()
```

This is what we get:
```
iex(6)> EctoLock.Helper.bill_from_two_servers()
#PID<0.235.0>
iex(7)>
13:01:33.138 [debug] QUERY OK source="invoices" db=1.5ms queue=0.1ms
SELECT i0."id", i0."pending" FROM "invoices" AS i0 WHERE (i0."pending" = TRUE) []

13:01:33.139 [debug] QUERY OK source="invoices" db=2.0ms
SELECT i0."id", i0."pending" FROM "invoices" AS i0 WHERE (i0."pending" = TRUE) []

13:01:33.141 [debug] QUERY ERROR source="invoices" db=2.0ms queue=0.1ms
SELECT i0."id", i0."pending" FROM "invoices" AS i0 WHERE (i0."id" = $1) FOR UPDATE NOWAIT [14]
Sending invoice 14...
iex(7)>
13:01:33.141 [debug] QUERY OK source="invoices" db=2.7ms
SELECT i0."id", i0."pending" FROM "invoices" AS i0 WHERE (i0."id" = $1) FOR UPDATE NOWAIT [14]

13:01:33.142 [error] Process #PID<0.235.0> raised an exception
** (Postgrex.Error) ERROR 55P03 (lock_not_available) could not obtain lock on row in relation "invoices"
    (ecto_sql) lib/ecto/adapters/sql.ex:595: Ecto.Adapters.SQL.raise_sql_call_error/1
    (ecto_sql) lib/ecto/adapters/sql.ex:528: Ecto.Adapters.SQL.execute/5
    (ecto) lib/ecto/repo/queryable.ex:147: Ecto.Repo.Queryable.execute/4
    (ecto) lib/ecto/repo/queryable.ex:18: Ecto.Repo.Queryable.all/3
    (ecto) lib/ecto/repo/queryable.ex:66: Ecto.Repo.Queryable.one/3
    (ecto_lock) lib/ecto_lock/bill_pending_invoices.ex:17: EctoLock.BillPendingInvoices.bill_pending_invoice/1
    (elixir) lib/enum.ex:765: Enum."-each/2-lists^foreach/1-0-"/2
    (elixir) lib/enum.ex:765: Enum.each/2
Invoice 14 sent!
iex(7)>
13:01:34.146 [debug] QUERY OK db=2.8ms queue=0.7ms
UPDATE "invoices" SET "pending" = $1 WHERE "id" = $2 [false, 14]
Sending invoice 15...
Invoice 15 sent!
Sending invoice 16...
Invoice 16 sent!
```

>Note: I've removed some of the SQL messages here, but not all of them.

Alright! We can see that we've solved the problem! Now each invoice is only being sent one time! Taking a closer look at the return though, we now have a new issue.

Whichever server _did not_ get the database lock ended up throwing the following error: `** (Postgrex.Error) ERROR 55P03 (lock_not_available) could not obtain lock on row in relation "invoices"`. This isn't great. It means that our server is going to be constantly throwing unhandled errors _and_ we can see that once it failed for one invoice, it didn't try and take care of any more. Let's see if we can handle this error and make things a little more performant.

If at first you don't succeed, try again!

What we want to do here is safely rescue this error in the event that things don't work out. Let's update `bill_pending_invoice/1` in our `EctoLock.BillPendingInvoices` module to look like this:

```elixir
def bill_pending_invoice(invoice_id) do
  try do
    invoice = get_invoice(invoice_id)
    bill_through_api(invoice)
    mark_invoice_sent(invoice)
  rescue
    e in Postgrex.Error -> {:ok, e}
  end
end
```

Here we are using Elixir's [try/rescue](https://elixir-lang.org/getting-started/try-catch-and-rescue.html) functionality to safely catch this specific error.

>Note: that we only want to catch this specific error and not just _any_ error. If another error get's thrown, we definitely want to be alerted to the problem and not just cover it up with news paper. (Insert Big Daddy gif?)

Now that we can this in place, let's restart our elixir console and try this again:

```elixir
EctoLock.Helper.create_invoices()
EctoLock.Helper.bill_from_two_servers()
```

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
