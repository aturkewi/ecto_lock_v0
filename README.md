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

Feeling the pain

Now let’s write some code such that we actually run into this locking issue. Let’s create a new file at `lib/ecto_lock/bill_pending_invoices.ex` and fill it with the following:



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
