module Pylonite
  module Help
    def self.display
      puts <<~HELP
        \e[1mpylonite\e[0m - project task management from the command line

        \e[1mTASK CREATION & EDITING\e[0m

          pylonite add "task title"
            Create a new task in the backlog.
            Options:
              --board BOARD         Set initial board (backlog, todo, in_progress, done, archived)
              --assign USER         Assign to a user
              --description "text"  Set description (-d "text" also works)
            Examples:
              pylonite add "Fix login bug"
              pylonite add "Deploy v2" --board todo --assign alice -d "Deploy to production"

          pylonite edit ID
            Update an existing task's title or description.
            Options:
              --title "new title"
              --description "new desc"  (-d "new desc" also works)
            Examples:
              pylonite edit 3 --title "Fix login bug (urgent)"
              pylonite edit 3 -d "Updated requirements from client"

          pylonite subtask PARENT_ID "title"
            Create a subtask under an existing task.
            Example:
              pylonite subtask 1 "Write unit tests"

        \e[1mTASK VIEWING\e[0m

          pylonite show ID
            Show full task details: title, board, author, assignee, description,
            blockers, subtasks, comments, and history.
            Example:
              pylonite show 1

          pylonite list
            List all non-archived tasks grouped by board.
            Options:
              --board BOARD   Show only tasks in a specific board
              --all           Include archived tasks
            Examples:
              pylonite list
              pylonite list --board in_progress
              pylonite list --all

          pylonite search "query"
            Search tasks by title and description.
            Example:
              pylonite search "login"

        \e[1mTASK WORKFLOW\e[0m

          pylonite move ID BOARD
            Move a task to a board.
            Boards: backlog, todo, in_progress, done, archived
            Example:
              pylonite move 1 in_progress

          pylonite archive ID
            Archive a task (shortcut for move ID archived).
            Example:
              pylonite archive 5

          pylonite assign ID USER
            Assign a task to a user.
            Example:
              pylonite assign 1 alice

        \e[1mCOMMENTS\e[0m

          pylonite comment ID "comment text"
            Add a comment to a task.
            Example:
              pylonite comment 1 "Blocked on API changes"

        \e[1mDEPENDENCIES\e[0m

          pylonite block ID BLOCKER_ID
            Mark BLOCKER_ID as blocking ID (ID cannot proceed until BLOCKER_ID is resolved).
            Example:
              pylonite block 3 1    # task 1 blocks task 3

          pylonite unblock ID BLOCKER_ID
            Remove a blocker relationship.
            Example:
              pylonite unblock 3 1

        \e[1mACTIVITY\e[0m

          pylonite log
            Show full activity log (most recent first) in a pager.
            All task events: creation, moves, comments, assignments, etc.
            Uses $PAGER or falls back to `less -R`.
            Example:
              pylonite log

        \e[1mOTHER\e[0m

          pylonite tui
            Launch the interactive terminal UI.

          pylonite help
            Show this help message.

          pylonite internal appropriate OLD_DB_PATH
            Rename/move an existing database file to match the current project directory.
            Used when a project directory has been moved or renamed.
            Example:
              pylonite internal appropriate ~/.pylonite/dbs/old_project_abc123.sqlite3

        \e[1mBOARDS\e[0m

          backlog      Default board for new tasks
          todo         Tasks ready to be worked on
          in_progress  Tasks currently being worked on
          done         Completed tasks
          archived     Archived tasks (hidden from default list)

        \e[1mNOTES\e[0m

          - Each project directory gets its own task database (~/.pylonite/dbs/)
          - Task IDs are integers, auto-incremented per project
          - The current $USER is recorded as author/actor for all operations
          - All timestamps are UTC ISO 8601
      HELP
    end
  end
end
