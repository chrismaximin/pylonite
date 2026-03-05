# Git Conventions
- Commit after completing work
- Keep commit messages concise and focused on "why" not "what"

# Project Structure
- `lib/pylonite/database.rb` — SQLite database layer (schema, CRUD, migrations)
- `lib/pylonite/cli.rb` — CLI command dispatcher (all `pylonite <command>` handling)
- `lib/pylonite/tui.rb` — Interactive terminal UI (board view, detail view)
- `lib/pylonite/help.rb` — Help text displayed by `pylonite help`
- `bin/pylonite` — Executable entry point
- `test/` — Minitest suite, run with `rake test`

# Database Migrations
The database uses a versioned migration system via SQLite's `PRAGMA user_version`.

**When adding a feature that changes the DB schema:**
1. Append a new SQL string to the `MIGRATIONS` array in `lib/pylonite/database.rb`
2. Never modify or reorder existing migrations — only append
3. Each migration runs in a transaction and auto-increments the schema version
4. Existing databases are upgraded incrementally on next open
5. Add tests for the new migration in `test/test_database.rb`

Example — adding a `priority` column to tasks:
```ruby
MIGRATIONS = [
  # Version 1: Initial schema
  <<~SQL
    CREATE TABLE tasks (...);
    ...
  SQL
  # Version 2: Add priority to tasks
  <<~SQL
    ALTER TABLE tasks ADD COLUMN priority TEXT DEFAULT 'medium';
  SQL
].freeze
```
