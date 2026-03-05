require_relative "test_helper"

class TestDatabase < Minitest::Test
  include Pylonite::TestHelper

  def setup
    setup_test_db
  end

  def teardown
    teardown_test_db
  end

  # --- DB creation and naming ---

  def test_db_name_includes_basename_and_hash
    name = Pylonite::Database.db_name_for("/home/user/my_project")
    assert_match(/^my_project_[a-f0-9]{8}$/, name)
  end

  def test_different_paths_produce_different_names
    name1 = Pylonite::Database.db_name_for("/home/user/project_a")
    name2 = Pylonite::Database.db_name_for("/home/user/project_b")
    refute_equal name1, name2
  end

  def test_same_path_produces_same_name
    name1 = Pylonite::Database.db_name_for("/home/user/project")
    name2 = Pylonite::Database.db_name_for("/home/user/project")
    assert_equal name1, name2
  end

  def test_db_file_created_on_initialize
    assert File.exist?(@db.db_path)
  end

  def test_db_path_ends_with_sqlite3
    assert @db.db_path.end_with?(".sqlite3")
  end

  # --- Task CRUD ---

  def test_add_task_returns_id
    id = @db.add_task("My task", author: "alice")
    assert_kind_of Integer, id
    assert id > 0
  end

  def test_add_task_defaults_to_backlog
    id = @db.add_task("My task", author: "alice")
    task = @db.get_task(id)
    assert_equal "backlog", task["board"]
  end

  def test_add_task_with_custom_board
    id = @db.add_task("My task", author: "alice", board: "todo")
    task = @db.get_task(id)
    assert_equal "todo", task["board"]
  end

  def test_add_task_with_description
    id = @db.add_task("My task", author: "alice", description: "Details here")
    task = @db.get_task(id)
    assert_equal "Details here", task["description"]
  end

  def test_add_task_with_assignee
    id = @db.add_task("My task", author: "alice", assignee: "bob")
    task = @db.get_task(id)
    assert_equal "bob", task["assignee"]
  end

  def test_add_task_records_author
    id = @db.add_task("My task", author: "alice")
    task = @db.get_task(id)
    assert_equal "alice", task["author"]
  end

  def test_add_task_sets_timestamps
    id = @db.add_task("My task", author: "alice")
    task = @db.get_task(id)
    refute_nil task["created_at"]
    refute_nil task["updated_at"]
  end

  def test_add_task_creates_history_entry
    id = @db.add_task("My task", author: "alice")
    task = @db.get_task(id)
    assert_equal 1, task["history"].length
    assert_equal "created", task["history"][0]["action"]
    assert_equal "alice", task["history"][0]["actor"]
  end

  def test_get_task_returns_nil_for_missing
    assert_nil @db.get_task(999)
  end

  def test_get_task_includes_all_associations
    id = @db.add_task("My task", author: "alice")
    task = @db.get_task(id)
    assert_kind_of Array, task["comments"]
    assert_kind_of Array, task["history"]
    assert_kind_of Array, task["blockers"]
    assert_kind_of Array, task["blocked_by_this"]
    assert_kind_of Array, task["subtasks"]
  end

  def test_auto_increment_ids
    id1 = @db.add_task("First", author: "alice")
    id2 = @db.add_task("Second", author: "alice")
    assert_equal id1 + 1, id2
  end

  # --- List tasks ---

  def test_list_tasks_returns_all_non_archived
    @db.add_task("Backlog task", author: "a")
    @db.add_task("Todo task", author: "a", board: "todo")
    id3 = @db.add_task("Archived task", author: "a")
    @db.archive_task(id3)

    tasks = @db.list_tasks
    assert_equal 2, tasks.length
    boards = tasks.map { |t| t["board"] }
    refute_includes boards, "archived"
  end

  def test_list_tasks_with_include_archived
    @db.add_task("Backlog task", author: "a")
    id2 = @db.add_task("Archived task", author: "a")
    @db.archive_task(id2)

    tasks = @db.list_tasks(include_archived: true)
    assert_equal 2, tasks.length
  end

  def test_list_tasks_by_board
    @db.add_task("Backlog task", author: "a")
    @db.add_task("Todo task", author: "a", board: "todo")

    tasks = @db.list_tasks(board: "todo")
    assert_equal 1, tasks.length
    assert_equal "todo", tasks[0]["board"]
  end

  def test_list_tasks_empty
    tasks = @db.list_tasks
    assert_empty tasks
  end

  # --- Move task ---

  def test_move_task_changes_board
    id = @db.add_task("My task", author: "alice")
    @db.move_task(id, "in_progress")
    task = @db.get_task(id)
    assert_equal "in_progress", task["board"]
  end

  def test_move_task_records_history
    id = @db.add_task("My task", author: "alice")
    @db.move_task(id, "in_progress", actor: "bob")
    task = @db.get_task(id)
    move_entry = task["history"].find { |h| h["action"] == "moved" }
    refute_nil move_entry
    assert_equal "bob", move_entry["actor"]
    assert_includes move_entry["detail"], "backlog"
    assert_includes move_entry["detail"], "in_progress"
  end

  def test_move_task_updates_timestamp
    id = @db.add_task("My task", author: "alice")
    original = @db.get_task(id)["updated_at"]
    sleep 0.01
    @db.move_task(id, "done")
    updated = @db.get_task(id)["updated_at"]
    assert updated >= original
  end

  def test_move_task_invalid_board_raises
    id = @db.add_task("My task", author: "alice")
    assert_raises(RuntimeError) { @db.move_task(id, "nonexistent") }
  end

  def test_move_task_missing_task_raises
    assert_raises(RuntimeError) { @db.move_task(999, "todo") }
  end

  def test_move_to_all_valid_boards
    Pylonite::Database::BOARDS.each do |board|
      id = @db.add_task("Task for #{board}", author: "a")
      @db.move_task(id, board)
      assert_equal board, @db.get_task(id)["board"]
    end
  end

  # --- Archive ---

  def test_archive_task
    id = @db.add_task("My task", author: "alice")
    @db.archive_task(id)
    task = @db.get_task(id)
    assert_equal "archived", task["board"]
  end

  def test_archive_task_with_actor
    id = @db.add_task("My task", author: "alice")
    @db.archive_task(id, actor: "bob")
    task = @db.get_task(id)
    move_entry = task["history"].find { |h| h["action"] == "moved" }
    assert_equal "bob", move_entry["actor"]
  end

  # --- Assign ---

  def test_assign_task
    id = @db.add_task("My task", author: "alice")
    @db.assign_task(id, "bob")
    task = @db.get_task(id)
    assert_equal "bob", task["assignee"]
  end

  def test_assign_task_records_history
    id = @db.add_task("My task", author: "alice")
    @db.assign_task(id, "bob", actor: "alice")
    task = @db.get_task(id)
    assign_entry = task["history"].find { |h| h["action"] == "assigned" }
    refute_nil assign_entry
    assert_equal "alice", assign_entry["actor"]
    assert_includes assign_entry["detail"], "bob"
  end

  def test_assign_task_missing_raises
    assert_raises(RuntimeError) { @db.assign_task(999, "bob") }
  end

  def test_reassign_task
    id = @db.add_task("My task", author: "alice")
    @db.assign_task(id, "bob")
    @db.assign_task(id, "charlie")
    task = @db.get_task(id)
    assert_equal "charlie", task["assignee"]
  end

  # --- Update task ---

  def test_update_task_title
    id = @db.add_task("Old title", author: "alice")
    @db.update_task(id, title: "New title")
    task = @db.get_task(id)
    assert_equal "New title", task["title"]
  end

  def test_update_task_description
    id = @db.add_task("My task", author: "alice")
    @db.update_task(id, description: "New description")
    task = @db.get_task(id)
    assert_equal "New description", task["description"]
  end

  def test_update_task_both
    id = @db.add_task("Old", author: "alice")
    @db.update_task(id, title: "New", description: "Desc")
    task = @db.get_task(id)
    assert_equal "New", task["title"]
    assert_equal "Desc", task["description"]
  end

  def test_update_task_records_history
    id = @db.add_task("My task", author: "alice")
    @db.update_task(id, title: "Updated", actor: "bob")
    task = @db.get_task(id)
    update_entry = task["history"].find { |h| h["action"] == "updated" }
    refute_nil update_entry
    assert_equal "bob", update_entry["actor"]
  end

  def test_update_task_missing_raises
    assert_raises(RuntimeError) { @db.update_task(999, title: "X") }
  end

  def test_update_task_noop_when_nothing_given
    id = @db.add_task("My task", author: "alice")
    original = @db.get_task(id)["updated_at"]
    @db.update_task(id)
    assert_equal original, @db.get_task(id)["updated_at"]
  end

  # --- Search ---

  def test_search_by_title
    @db.add_task("Fix compiler bug", author: "alice")
    @db.add_task("Write tests", author: "alice")
    results = @db.search_tasks("compiler")
    assert_equal 1, results.length
    assert_equal "Fix compiler bug", results[0]["title"]
  end

  def test_search_by_description
    @db.add_task("My task", author: "alice", description: "This involves the parser module")
    @db.add_task("Other task", author: "alice")
    results = @db.search_tasks("parser")
    assert_equal 1, results.length
  end

  def test_search_case_insensitive_via_like
    @db.add_task("Fix Bug", author: "alice")
    results = @db.search_tasks("fix")
    assert_equal 1, results.length
  end

  def test_search_no_results
    @db.add_task("Something", author: "alice")
    results = @db.search_tasks("nonexistent")
    assert_empty results
  end

  def test_search_partial_match
    @db.add_task("Fix compiler bug", author: "alice")
    results = @db.search_tasks("compil")
    assert_equal 1, results.length
  end

  # --- Comments ---

  def test_add_comment
    id = @db.add_task("My task", author: "alice")
    comment_id = @db.add_comment(id, "A comment", author: "bob")
    assert comment_id > 0
  end

  def test_comment_appears_on_task
    id = @db.add_task("My task", author: "alice")
    @db.add_comment(id, "First comment", author: "bob")
    @db.add_comment(id, "Second comment", author: "charlie")
    task = @db.get_task(id)
    assert_equal 2, task["comments"].length
    assert_equal "First comment", task["comments"][0]["text"]
    assert_equal "bob", task["comments"][0]["author"]
    assert_equal "Second comment", task["comments"][1]["text"]
  end

  def test_comment_records_history
    id = @db.add_task("My task", author: "alice")
    @db.add_comment(id, "A comment", author: "bob")
    task = @db.get_task(id)
    comment_entry = task["history"].find { |h| h["action"] == "commented" }
    refute_nil comment_entry
    assert_equal "bob", comment_entry["actor"]
  end

  def test_comment_updates_task_timestamp
    id = @db.add_task("My task", author: "alice")
    original = @db.get_task(id)["updated_at"]
    sleep 0.01
    @db.add_comment(id, "A comment")
    assert @db.get_task(id)["updated_at"] >= original
  end

  def test_comment_on_missing_task_raises
    assert_raises(RuntimeError) { @db.add_comment(999, "comment") }
  end

  # --- Blockers ---

  def test_add_blocker
    id1 = @db.add_task("Task A", author: "alice")
    id2 = @db.add_task("Task B", author: "alice")
    @db.add_blocker(id1, id2)
    task = @db.get_task(id1)
    assert_equal 1, task["blockers"].length
    assert_equal id2, task["blockers"][0]["id"]
  end

  def test_blocker_reverse_relationship
    id1 = @db.add_task("Task A", author: "alice")
    id2 = @db.add_task("Task B", author: "alice")
    @db.add_blocker(id1, id2)
    task_b = @db.get_task(id2)
    assert_equal 1, task_b["blocked_by_this"].length
    assert_equal id1, task_b["blocked_by_this"][0]["id"]
  end

  def test_remove_blocker
    id1 = @db.add_task("Task A", author: "alice")
    id2 = @db.add_task("Task B", author: "alice")
    @db.add_blocker(id1, id2)
    @db.remove_blocker(id1, id2)
    task = @db.get_task(id1)
    assert_empty task["blockers"]
  end

  def test_self_block_raises
    id = @db.add_task("Task", author: "alice")
    assert_raises(RuntimeError) { @db.add_blocker(id, id) }
  end

  def test_block_missing_task_raises
    id = @db.add_task("Task", author: "alice")
    assert_raises(RuntimeError) { @db.add_blocker(999, id) }
    assert_raises(RuntimeError) { @db.add_blocker(id, 999) }
  end

  def test_duplicate_blocker_is_ignored
    id1 = @db.add_task("Task A", author: "alice")
    id2 = @db.add_task("Task B", author: "alice")
    @db.add_blocker(id1, id2)
    @db.add_blocker(id1, id2) # should not raise
    task = @db.get_task(id1)
    assert_equal 1, task["blockers"].length
  end

  def test_blocker_records_history
    id1 = @db.add_task("Task A", author: "alice")
    id2 = @db.add_task("Task B", author: "alice")
    @db.add_blocker(id1, id2, actor: "bob")
    task = @db.get_task(id1)
    entry = task["history"].find { |h| h["action"] == "blocker_added" }
    refute_nil entry
    assert_equal "bob", entry["actor"]
  end

  def test_multiple_blockers
    id1 = @db.add_task("Blocked task", author: "alice")
    id2 = @db.add_task("Blocker 1", author: "alice")
    id3 = @db.add_task("Blocker 2", author: "alice")
    @db.add_blocker(id1, id2)
    @db.add_blocker(id1, id3)
    task = @db.get_task(id1)
    assert_equal 2, task["blockers"].length
  end

  # --- Subtasks ---

  def test_add_subtask
    parent_id = @db.add_task("Parent", author: "alice")
    sub_id = @db.add_subtask(parent_id, "Subtask", author: "alice")
    assert sub_id > parent_id
  end

  def test_subtask_appears_on_parent
    parent_id = @db.add_task("Parent", author: "alice")
    sub_id = @db.add_subtask(parent_id, "Subtask", author: "alice")
    parent = @db.get_task(parent_id)
    assert_equal 1, parent["subtasks"].length
    assert_equal sub_id, parent["subtasks"][0]["id"]
  end

  def test_subtask_knows_parent
    parent_id = @db.add_task("Parent", author: "alice")
    sub_id = @db.add_subtask(parent_id, "Subtask", author: "alice")
    subtask = @db.get_task(sub_id)
    refute_nil subtask["parent"]
    assert_equal parent_id, subtask["parent"]["id"]
  end

  def test_subtask_is_in_backlog
    parent_id = @db.add_task("Parent", author: "alice")
    sub_id = @db.add_subtask(parent_id, "Subtask", author: "alice")
    subtask = @db.get_task(sub_id)
    assert_equal "backlog", subtask["board"]
  end

  def test_subtask_records_history_on_both
    parent_id = @db.add_task("Parent", author: "alice")
    sub_id = @db.add_subtask(parent_id, "Subtask", author: "bob")
    parent = @db.get_task(parent_id)
    subtask = @db.get_task(sub_id)

    parent_entry = parent["history"].find { |h| h["action"] == "subtask_added" }
    refute_nil parent_entry
    assert_equal "bob", parent_entry["actor"]

    sub_entry = subtask["history"].find { |h| h["action"] == "subtask_created" }
    refute_nil sub_entry
  end

  def test_subtask_missing_parent_raises
    assert_raises(RuntimeError) { @db.add_subtask(999, "Orphan") }
  end

  def test_multiple_subtasks
    parent_id = @db.add_task("Parent", author: "alice")
    @db.add_subtask(parent_id, "Sub 1", author: "alice")
    @db.add_subtask(parent_id, "Sub 2", author: "alice")
    @db.add_subtask(parent_id, "Sub 3", author: "alice")
    parent = @db.get_task(parent_id)
    assert_equal 3, parent["subtasks"].length
  end

  # --- History ---

  def test_history_is_ordered_chronologically
    id = @db.add_task("Task", author: "alice")
    @db.move_task(id, "in_progress")
    @db.add_comment(id, "comment")
    @db.move_task(id, "done")
    task = @db.get_task(id)
    timestamps = task["history"].map { |h| h["created_at"] }
    assert_equal timestamps, timestamps.sort
  end

  def test_full_lifecycle_history
    id = @db.add_task("Task", author: "alice")
    @db.assign_task(id, "bob")
    @db.move_task(id, "in_progress")
    @db.add_comment(id, "Working on it")
    @db.move_task(id, "done")
    task = @db.get_task(id)
    actions = task["history"].map { |h| h["action"] }
    assert_equal %w[created assigned moved commented moved], actions
  end

  # --- Appropriate ---

  def test_appropriate_moves_db_file
    old_path = @db.db_path
    @db.close

    new_project = File.join(@tmpdir, "renamed_project")
    new_db_path = Pylonite::Database.appropriate(new_project, old_path)

    assert File.exist?(new_db_path)
    refute File.exist?(old_path)
    assert new_db_path.include?("renamed_project")
  end

  def test_appropriate_missing_db_raises
    assert_raises(RuntimeError) { Pylonite::Database.appropriate("/tmp/x", "/nonexistent/path.sqlite3") }
  end

  # --- Default author ---

  def test_default_author_uses_env_user
    id = @db.add_task("Task")
    task = @db.get_task(id)
    expected = ENV["USER"] || ENV["USERNAME"] || "unspecified"
    assert_equal expected, task["author"]
  end

  # --- Close ---

  def test_close_does_not_raise
    @db.close
    @db = nil # prevent double close in teardown
  end
end
