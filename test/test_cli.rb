require_relative "test_helper"

class TestCLI < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("pylonite_cli_test")
    @project_path = File.join(@tmpdir, "test_project")
    FileUtils.mkdir_p(@project_path)
    @original_dir = Dir.pwd
    Dir.chdir(@project_path)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tmpdir)
  end

  def run_cli(*args)
    stdout, stderr = capture_io do
      begin
        Pylonite::CLI.run(args.flatten)
      rescue SystemExit
        # CLI calls exit(1) on error
      end
    end
    [stdout, stderr]
  end

  def db
    Pylonite::Database.new(File.realpath(@project_path))
  end

  # --- add ---

  def test_add_basic
    stdout, _ = run_cli("add", "Fix the bug")
    assert_match(/#1/, stdout)
    assert_match(/backlog/, stdout)

    task = db.get_task(1)
    assert_equal "Fix the bug", task["title"]
    assert_equal "backlog", task["board"]
  end

  def test_add_with_board
    stdout, _ = run_cli("add", "Deploy", "--board", "todo")
    assert_match(/todo/, stdout)
    assert_equal "todo", db.get_task(1)["board"]
  end

  def test_add_with_assign
    run_cli("add", "Task", "--assign", "alice")
    assert_equal "alice", db.get_task(1)["assignee"]
  end

  def test_add_with_description
    run_cli("add", "Task", "--description", "Some details")
    assert_equal "Some details", db.get_task(1)["description"]
  end

  def test_add_with_short_description
    run_cli("add", "Task", "-d", "Short desc")
    assert_equal "Short desc", db.get_task(1)["description"]
  end

  def test_add_with_all_options
    run_cli("add", "Full task", "--board", "in_progress", "--assign", "bob", "-d", "Details")
    task = db.get_task(1)
    assert_equal "Full task", task["title"]
    assert_equal "in_progress", task["board"]
    assert_equal "bob", task["assignee"]
    assert_equal "Details", task["description"]
  end

  def test_add_no_title_errors
    _, stderr = run_cli("add")
    assert_match(/Usage/, stderr)
  end

  # --- show ---

  def test_show_basic
    run_cli("add", "My task", "-d", "Task description")
    stdout, _ = run_cli("show", "1")
    assert_match(/My task/, stdout)
    assert_match(/backlog/, stdout)
    assert_match(/Task description/, stdout)
  end

  def test_show_with_comments
    run_cli("add", "My task")
    run_cli("comment", "1", "A comment")
    stdout, _ = run_cli("show", "1")
    assert_match(/A comment/, stdout)
  end

  def test_show_with_blockers
    run_cli("add", "Blocked")
    run_cli("add", "Blocker")
    run_cli("block", "1", "2")
    stdout, _ = run_cli("show", "1")
    assert_match(/Blocked by/, stdout)
    assert_match(/Blocker/, stdout)
  end

  def test_show_with_subtasks
    run_cli("add", "Parent")
    run_cli("subtask", "1", "Child")
    stdout, _ = run_cli("show", "1")
    assert_match(/Subtasks/, stdout)
    assert_match(/Child/, stdout)
  end

  def test_show_subtask_shows_parent
    run_cli("add", "Parent")
    run_cli("subtask", "1", "Child")
    stdout, _ = run_cli("show", "2")
    assert_match(/Parent/, stdout)
  end

  def test_show_with_history
    run_cli("add", "Task")
    run_cli("move", "1", "in_progress")
    stdout, _ = run_cli("show", "1")
    assert_match(/History/, stdout)
    assert_match(/Created task/, stdout)
    assert_match(/Moved from/, stdout)
  end

  def test_show_missing_task_errors
    _, stderr = run_cli("show", "999")
    assert_match(/not found/, stderr)
  end

  def test_show_no_id_errors
    _, stderr = run_cli("show")
    assert_match(/Usage/, stderr)
  end

  def test_show_assignee
    run_cli("add", "Task")
    run_cli("assign", "1", "bob")
    stdout, _ = run_cli("show", "1")
    assert_match(/bob/, stdout)
  end

  # --- list ---

  def test_list_groups_by_board
    run_cli("add", "Backlog task")
    run_cli("add", "Todo task", "--board", "todo")
    stdout, _ = run_cli("list")
    assert_match(/BACKLOG/, stdout)
    assert_match(/TODO/, stdout)
    assert_match(/Backlog task/, stdout)
    assert_match(/Todo task/, stdout)
  end

  def test_list_excludes_archived_by_default
    run_cli("add", "Active")
    run_cli("add", "Old")
    run_cli("archive", "2")
    stdout, _ = run_cli("list")
    assert_match(/Active/, stdout)
    refute_match(/ARCHIVED/, stdout)
  end

  def test_list_all_includes_archived
    run_cli("add", "Old")
    run_cli("archive", "1")
    stdout, _ = run_cli("list", "--all")
    assert_match(/ARCHIVED/, stdout)
    assert_match(/Old/, stdout)
  end

  def test_list_by_board
    run_cli("add", "Backlog task")
    run_cli("add", "Todo task", "--board", "todo")
    stdout, _ = run_cli("list", "--board", "todo")
    refute_match(/BACKLOG/, stdout)
    assert_match(/TODO/, stdout)
  end

  def test_list_empty
    stdout, _ = run_cli("list")
    assert_match(/No tasks found/, stdout)
  end

  def test_list_shows_assignee
    run_cli("add", "Task", "--assign", "bob")
    stdout, _ = run_cli("list")
    assert_match(/bob/, stdout)
  end

  # --- move ---

  def test_move
    run_cli("add", "Task")
    stdout, _ = run_cli("move", "1", "in_progress")
    assert_match(/Moved/, stdout)
    assert_match(/in_progress/, stdout)
    assert_equal "in_progress", db.get_task(1)["board"]
  end

  def test_move_no_args_errors
    _, stderr = run_cli("move")
    assert_match(/Usage/, stderr)
  end

  def test_move_invalid_board_errors
    run_cli("add", "Task")
    _, stderr = run_cli("move", "1", "invalid")
    assert_match(/Invalid board/, stderr)
  end

  # --- comment ---

  def test_comment
    run_cli("add", "Task")
    stdout, _ = run_cli("comment", "1", "My comment")
    assert_match(/Comment added/, stdout)
    task = db.get_task(1)
    assert_equal 1, task["comments"].length
    assert_equal "My comment", task["comments"][0]["text"]
  end

  def test_comment_no_args_errors
    _, stderr = run_cli("comment")
    assert_match(/Usage/, stderr)
  end

  # --- search ---

  def test_search
    run_cli("add", "Fix compiler bug")
    run_cli("add", "Write tests")
    stdout, _ = run_cli("search", "compiler")
    assert_match(/compiler/, stdout)
    refute_match(/Write tests/, stdout)
  end

  def test_search_no_results
    run_cli("add", "Something")
    stdout, _ = run_cli("search", "nonexistent")
    assert_match(/No tasks matching/, stdout)
  end

  def test_search_no_query_errors
    _, stderr = run_cli("search")
    assert_match(/Usage/, stderr)
  end

  # --- archive ---

  def test_archive
    run_cli("add", "Task")
    stdout, _ = run_cli("archive", "1")
    assert_match(/Archived/, stdout)
    assert_equal "archived", db.get_task(1)["board"]
  end

  def test_archive_no_id_errors
    _, stderr = run_cli("archive")
    assert_match(/Usage/, stderr)
  end

  # --- assign ---

  def test_assign
    run_cli("add", "Task")
    stdout, _ = run_cli("assign", "1", "alice")
    assert_match(/Assigned/, stdout)
    assert_match(/alice/, stdout)
    assert_equal "alice", db.get_task(1)["assignee"]
  end

  def test_assign_no_args_errors
    _, stderr = run_cli("assign")
    assert_match(/Usage/, stderr)
  end

  # --- block ---

  def test_block
    run_cli("add", "Task A")
    run_cli("add", "Task B")
    stdout, _ = run_cli("block", "1", "2")
    assert_match(/blocks/, stdout)
    task = db.get_task(1)
    assert_equal 1, task["blockers"].length
  end

  def test_block_no_args_errors
    _, stderr = run_cli("block")
    assert_match(/Usage/, stderr)
  end

  # --- unblock ---

  def test_unblock
    run_cli("add", "Task A")
    run_cli("add", "Task B")
    run_cli("block", "1", "2")
    stdout, _ = run_cli("unblock", "1", "2")
    assert_match(/Removed blocker/, stdout)
    assert_empty db.get_task(1)["blockers"]
  end

  def test_unblock_no_args_errors
    _, stderr = run_cli("unblock")
    assert_match(/Usage/, stderr)
  end

  # --- subtask ---

  def test_subtask
    run_cli("add", "Parent")
    stdout, _ = run_cli("subtask", "1", "Child task")
    assert_match(/subtask/, stdout)
    parent = db.get_task(1)
    assert_equal 1, parent["subtasks"].length
    assert_equal "Child task", parent["subtasks"][0]["title"]
  end

  def test_subtask_no_args_errors
    _, stderr = run_cli("subtask")
    assert_match(/Usage/, stderr)
  end

  # --- edit ---

  def test_edit_title
    run_cli("add", "Old title")
    stdout, _ = run_cli("edit", "1", "--title", "New title")
    assert_match(/Updated/, stdout)
    assert_equal "New title", db.get_task(1)["title"]
  end

  def test_edit_description
    run_cli("add", "Task")
    run_cli("edit", "1", "--description", "New desc")
    assert_equal "New desc", db.get_task(1)["description"]
  end

  def test_edit_short_description
    run_cli("add", "Task")
    run_cli("edit", "1", "-d", "Short desc")
    assert_equal "Short desc", db.get_task(1)["description"]
  end

  def test_edit_no_changes_errors
    run_cli("add", "Task")
    _, stderr = run_cli("edit", "1")
    assert_match(/Nothing to update/, stderr)
  end

  def test_edit_no_id_errors
    _, stderr = run_cli("edit")
    assert_match(/Usage/, stderr)
  end

  # --- internal appropriate ---

  def test_internal_appropriate
    # Create a DB under a different project name
    other_project = File.join(@tmpdir, "old_project")
    FileUtils.mkdir_p(other_project)
    real_other = File.realpath(other_project)
    other_db = Pylonite::Database.new(real_other)
    other_db.add_task("Task")
    old_path = other_db.db_path
    other_db.close

    stdout, _ = run_cli("internal", "appropriate", old_path)
    assert_match(/Database moved/, stdout)
    refute File.exist?(old_path)
  end

  def test_internal_appropriate_no_path_errors
    _, stderr = run_cli("internal", "appropriate")
    assert_match(/Usage/, stderr)
  end

  def test_internal_unknown_subcommand_errors
    _, stderr = run_cli("internal", "unknown")
    assert_match(/Unknown internal command/, stderr)
  end

  # --- help ---

  def test_help
    stdout, _ = run_cli("help")
    assert_match(/pylonite/, stdout)
    assert_match(/add/, stdout)
    assert_match(/show/, stdout)
    assert_match(/list/, stdout)
  end

  def test_help_flag
    stdout, _ = run_cli("--help")
    assert_match(/pylonite/, stdout)
  end

  def test_h_flag
    stdout, _ = run_cli("-h")
    assert_match(/pylonite/, stdout)
  end

  def test_no_args_shows_help
    stdout, _ = run_cli
    assert_match(/pylonite/, stdout)
  end

  # --- unknown command ---

  def test_unknown_command_errors
    _, stderr = run_cli("foobar")
    assert_match(/Unknown command/, stderr)
    assert_match(/foobar/, stderr)
  end
end
