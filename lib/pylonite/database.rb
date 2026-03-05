require "sqlite3"
require "fileutils"
require "digest"

module Pylonite
  class Database
    BOARDS = %w[backlog todo in_progress done archived].freeze
    DB_DIR = File.expand_path("~/.pylonite/dbs")

    attr_reader :db, :db_path

    def initialize(project_path = Dir.pwd)
      @db_path = self.class.db_path_for(project_path)
      FileUtils.mkdir_p(File.dirname(@db_path))
      @db = SQLite3::Database.new(@db_path)
      @db.results_as_hash = true
      @db.execute("PRAGMA journal_mode=WAL")
      @db.execute("PRAGMA foreign_keys=ON")
      migrate!
    end

    def self.db_name_for(project_path)
      name = File.basename(project_path)
      hash = Digest::SHA256.hexdigest(project_path)[0, 8]
      "#{name}_#{hash}"
    end

    def self.db_path_for(project_path)
      File.join(DB_DIR, "#{db_name_for(project_path)}.sqlite3")
    end

    def self.appropriate(new_path, old_db_path)
      raise "Database not found: #{old_db_path}" unless File.exist?(old_db_path)

      new_db_path = db_path_for(new_path)
      FileUtils.mkdir_p(File.dirname(new_db_path))
      FileUtils.mv(old_db_path, new_db_path)
      new_db_path
    end

    # --- Tasks ---

    def add_task(title, author: nil, board: "backlog", assignee: nil, description: nil)
      author ||= current_user
      now = Time.now.utc.iso8601
      @db.execute(
        "INSERT INTO tasks (title, description, board, author, assignee, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
        [title, description, board, author, assignee, now, now]
      )
      task_id = @db.last_insert_row_id
      record_history(task_id, author, "created", "Created task in #{board}")
      task_id
    end

    def get_task(task_id)
      task = @db.get_first_row("SELECT * FROM tasks WHERE id = ?", [task_id])
      return nil unless task

      task["comments"] = get_comments(task_id)
      task["history"] = get_history(task_id)
      task["blockers"] = get_blockers(task_id)
      task["blocked_by_this"] = get_blocked_by_this(task_id)
      task["subtasks"] = get_subtasks(task_id)
      task["parent"] = get_parent(task_id)
      task
    end

    def list_tasks(board: nil, include_archived: false)
      if board
        @db.execute("SELECT * FROM tasks WHERE board = ? ORDER BY updated_at DESC", [board])
      elsif include_archived
        @db.execute("SELECT * FROM tasks ORDER BY board, updated_at DESC")
      else
        @db.execute("SELECT * FROM tasks WHERE board != 'archived' ORDER BY board, updated_at DESC")
      end
    end

    def move_task(task_id, new_board, actor: nil)
      actor ||= current_user
      raise "Invalid board: #{new_board}. Valid boards: #{BOARDS.join(', ')}" unless BOARDS.include?(new_board)

      task = get_task(task_id)
      raise "Task ##{task_id} not found" unless task

      old_board = task["board"]
      now = Time.now.utc.iso8601
      @db.execute("UPDATE tasks SET board = ?, updated_at = ? WHERE id = ?", [new_board, now, task_id])
      record_history(task_id, actor, "moved", "Moved from #{old_board} to #{new_board}")
    end

    def archive_task(task_id, actor: nil)
      move_task(task_id, "archived", actor: actor)
    end

    def assign_task(task_id, assignee, actor: nil)
      actor ||= current_user
      task = get_task(task_id)
      raise "Task ##{task_id} not found" unless task

      now = Time.now.utc.iso8601
      @db.execute("UPDATE tasks SET assignee = ?, updated_at = ? WHERE id = ?", [assignee, now, task_id])
      record_history(task_id, actor, "assigned", "Assigned to #{assignee}")
    end

    def update_task(task_id, title: nil, description: nil, actor: nil)
      actor ||= current_user
      task = get_task(task_id)
      raise "Task ##{task_id} not found" unless task

      updates = []
      params = []
      if title
        updates << "title = ?"
        params << title
      end
      if description
        updates << "description = ?"
        params << description
      end
      return if updates.empty?

      updates << "updated_at = ?"
      params << Time.now.utc.iso8601
      params << task_id
      @db.execute("UPDATE tasks SET #{updates.join(', ')} WHERE id = ?", params)
      record_history(task_id, actor, "updated", "Updated task details")
    end

    def search_tasks(query)
      @db.execute(
        "SELECT * FROM tasks WHERE title LIKE ? OR description LIKE ? ORDER BY updated_at DESC",
        ["%#{query}%", "%#{query}%"]
      )
    end

    # --- Comments ---

    def add_comment(task_id, text, author: nil)
      author ||= current_user
      task = get_task(task_id)
      raise "Task ##{task_id} not found" unless task

      now = Time.now.utc.iso8601
      @db.execute(
        "INSERT INTO comments (task_id, author, text, created_at) VALUES (?, ?, ?, ?)",
        [task_id, author, text, now]
      )
      @db.execute("UPDATE tasks SET updated_at = ? WHERE id = ?", [now, task_id])
      record_history(task_id, author, "commented", "Added a comment")
      @db.last_insert_row_id
    end

    def get_comments(task_id)
      @db.execute("SELECT * FROM comments WHERE task_id = ? ORDER BY created_at ASC", [task_id])
    end

    # --- Dependencies ---

    def add_blocker(task_id, blocker_id, actor: nil)
      actor ||= current_user
      raise "Task cannot block itself" if task_id == blocker_id
      raise "Task ##{task_id} not found" unless get_task_raw(task_id)
      raise "Task ##{blocker_id} not found" unless get_task_raw(blocker_id)

      @db.execute(
        "INSERT OR IGNORE INTO task_dependencies (task_id, depends_on_id, dependency_type) VALUES (?, ?, 'blocks')",
        [task_id, blocker_id]
      )
      record_history(task_id, actor, "blocker_added", "Added blocker: task ##{blocker_id}")
    end

    def remove_blocker(task_id, blocker_id, actor: nil)
      actor ||= current_user
      @db.execute(
        "DELETE FROM task_dependencies WHERE task_id = ? AND depends_on_id = ? AND dependency_type = 'blocks'",
        [task_id, blocker_id]
      )
      record_history(task_id, actor, "blocker_removed", "Removed blocker: task ##{blocker_id}")
    end

    def get_blockers(task_id)
      @db.execute(
        "SELECT t.* FROM tasks t JOIN task_dependencies d ON d.depends_on_id = t.id WHERE d.task_id = ? AND d.dependency_type = 'blocks'",
        [task_id]
      )
    end

    def get_blocked_by_this(task_id)
      @db.execute(
        "SELECT t.* FROM tasks t JOIN task_dependencies d ON d.task_id = t.id WHERE d.depends_on_id = ? AND d.dependency_type = 'blocks'",
        [task_id]
      )
    end

    # --- Subtasks ---

    def add_subtask(parent_id, title, author: nil)
      author ||= current_user
      raise "Task ##{parent_id} not found" unless get_task_raw(parent_id)

      task_id = add_task(title, author: author)
      @db.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_id, dependency_type) VALUES (?, ?, 'subtask')",
        [task_id, parent_id]
      )
      record_history(task_id, author, "subtask_created", "Created as subtask of ##{parent_id}")
      record_history(parent_id, author, "subtask_added", "Added subtask ##{task_id}")
      task_id
    end

    def get_subtasks(task_id)
      @db.execute(
        "SELECT t.* FROM tasks t JOIN task_dependencies d ON d.task_id = t.id WHERE d.depends_on_id = ? AND d.dependency_type = 'subtask'",
        [task_id]
      )
    end

    def get_parent(task_id)
      @db.get_first_row(
        "SELECT t.* FROM tasks t JOIN task_dependencies d ON d.depends_on_id = t.id WHERE d.task_id = ? AND d.dependency_type = 'subtask'",
        [task_id]
      )
    end

    # --- History ---

    def get_history(task_id)
      @db.execute("SELECT * FROM task_history WHERE task_id = ? ORDER BY created_at ASC", [task_id])
    end

    def close
      @db.close
    end

    private

    def get_task_raw(task_id)
      @db.get_first_row("SELECT * FROM tasks WHERE id = ?", [task_id])
    end

    def current_user
      ENV["USER"] || ENV["USERNAME"] || "unspecified"
    end

    def record_history(task_id, actor, action, detail)
      now = Time.now.utc.iso8601
      @db.execute(
        "INSERT INTO task_history (task_id, actor, action, detail, created_at) VALUES (?, ?, ?, ?, ?)",
        [task_id, actor, action, detail, now]
      )
    end

    def migrate!
      @db.execute_batch(<<~SQL)
        CREATE TABLE IF NOT EXISTS tasks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          description TEXT,
          board TEXT NOT NULL DEFAULT 'backlog',
          author TEXT NOT NULL,
          assignee TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS comments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          task_id INTEGER NOT NULL,
          author TEXT NOT NULL,
          text TEXT NOT NULL,
          created_at TEXT NOT NULL,
          FOREIGN KEY (task_id) REFERENCES tasks(id)
        );

        CREATE TABLE IF NOT EXISTS task_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          task_id INTEGER NOT NULL,
          actor TEXT NOT NULL,
          action TEXT NOT NULL,
          detail TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (task_id) REFERENCES tasks(id)
        );

        CREATE TABLE IF NOT EXISTS task_dependencies (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          task_id INTEGER NOT NULL,
          depends_on_id INTEGER NOT NULL,
          dependency_type TEXT NOT NULL,
          FOREIGN KEY (task_id) REFERENCES tasks(id),
          FOREIGN KEY (depends_on_id) REFERENCES tasks(id),
          UNIQUE(task_id, depends_on_id, dependency_type)
        );

        CREATE INDEX IF NOT EXISTS idx_tasks_board ON tasks(board);
        CREATE INDEX IF NOT EXISTS idx_comments_task_id ON comments(task_id);
        CREATE INDEX IF NOT EXISTS idx_task_history_task_id ON task_history(task_id);
        CREATE INDEX IF NOT EXISTS idx_task_dependencies_task_id ON task_dependencies(task_id);
        CREATE INDEX IF NOT EXISTS idx_task_dependencies_depends_on ON task_dependencies(depends_on_id);
      SQL
    end
  end
end
