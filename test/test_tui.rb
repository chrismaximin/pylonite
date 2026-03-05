require_relative "test_helper"

class TestTUI < Minitest::Test
  include Pylonite::TestHelper

  def setup
    setup_test_db
  end

  def teardown
    teardown_test_db
  end

  # --- Helper methods ---

  def test_board_label
    assert_equal "Backlog", Pylonite::TUI.board_label("backlog")
    assert_equal "In Progress", Pylonite::TUI.board_label("in_progress")
    assert_equal "Done", Pylonite::TUI.board_label("done")
    assert_equal "Todo", Pylonite::TUI.board_label("todo")
    assert_equal "Archived", Pylonite::TUI.board_label("archived")
  end

  def test_truncate_short_string
    assert_equal "hello", Pylonite::TUI.truncate("hello", 10)
  end

  def test_truncate_exact_length
    assert_equal "hello", Pylonite::TUI.truncate("hello", 5)
  end

  def test_truncate_long_string
    result = Pylonite::TUI.truncate("hello world", 8)
    assert_equal "hello...", result
    assert_equal 8, result.length
  end

  def test_truncate_very_short_max
    result = Pylonite::TUI.truncate("hello", 3)
    assert_equal "hel", result
  end

  def test_wrap_text_short_line
    lines = Pylonite::TUI.wrap_text("Hello world", 80)
    assert_equal ["Hello world"], lines
  end

  def test_wrap_text_long_line
    text = "This is a very long line that should be wrapped at some point because it exceeds the width"
    lines = Pylonite::TUI.wrap_text(text, 30)
    lines.each { |line| assert line.length <= 30, "Line too long: #{line.inspect} (#{line.length})" }
  end

  def test_wrap_text_preserves_newlines
    lines = Pylonite::TUI.wrap_text("Line 1\nLine 2\nLine 3", 80)
    assert_equal ["Line 1", "Line 2", "Line 3"], lines
  end

  def test_wrap_text_empty_string
    lines = Pylonite::TUI.wrap_text("", 80)
    assert_equal [""], lines
  end

  def test_wrap_text_nil
    lines = Pylonite::TUI.wrap_text(nil, 80)
    assert_equal [""], lines
  end

  # --- Visible boards ---

  def test_visible_boards_default
    state = { show_archived: false }
    boards = Pylonite::TUI.visible_boards(state)
    assert_equal %w[backlog todo in_progress done], boards
    refute_includes boards, "archived"
  end

  def test_visible_boards_with_archived
    state = { show_archived: true }
    boards = Pylonite::TUI.visible_boards(state)
    assert_equal %w[backlog todo in_progress done archived], boards
  end

  # --- Board data loading ---

  def test_load_board_tasks_groups_by_board
    @db.add_task("Backlog task", author: "a")
    @db.add_task("Todo task", author: "a", board: "todo")
    state = { db: @db, show_archived: false }
    grouped = Pylonite::TUI.load_board_tasks(state)
    assert_equal 1, grouped["backlog"].length
    assert_equal 1, grouped["todo"].length
  end

  def test_load_board_tasks_empty
    state = { db: @db, show_archived: false }
    grouped = Pylonite::TUI.load_board_tasks(state)
    assert_empty grouped
  end

  # --- Detail lines ---

  def test_build_detail_lines_includes_title
    id = @db.add_task("My task", author: "alice")
    task = @db.get_task(id)
    lines = Pylonite::TUI.build_detail_lines(task, 80)
    joined = lines.join("\n")
    assert_match(/My task/, joined)
  end

  def test_build_detail_lines_includes_board
    id = @db.add_task("Task", author: "alice", board: "todo")
    task = @db.get_task(id)
    lines = Pylonite::TUI.build_detail_lines(task, 80)
    joined = lines.join("\n")
    assert_match(/Todo/, joined)
  end

  def test_build_detail_lines_includes_description
    id = @db.add_task("Task", author: "alice", description: "My description")
    task = @db.get_task(id)
    lines = Pylonite::TUI.build_detail_lines(task, 80)
    joined = lines.join("\n")
    assert_match(/Description/, joined)
    assert_match(/My description/, joined)
  end

  def test_build_detail_lines_includes_comments
    id = @db.add_task("Task", author: "alice")
    @db.add_comment(id, "A comment", author: "bob")
    task = @db.get_task(id)
    lines = Pylonite::TUI.build_detail_lines(task, 80)
    joined = lines.join("\n")
    assert_match(/Comments/, joined)
    assert_match(/A comment/, joined)
    assert_match(/bob/, joined)
  end

  def test_build_detail_lines_includes_history
    id = @db.add_task("Task", author: "alice")
    @db.move_task(id, "in_progress")
    task = @db.get_task(id)
    lines = Pylonite::TUI.build_detail_lines(task, 80)
    joined = lines.join("\n")
    assert_match(/History/, joined)
    assert_match(/Created task/, joined)
    assert_match(/Moved from/, joined)
  end

  def test_build_detail_lines_includes_subtasks
    parent = @db.add_task("Parent", author: "alice")
    @db.add_subtask(parent, "Child", author: "alice")
    task = @db.get_task(parent)
    lines = Pylonite::TUI.build_detail_lines(task, 80)
    joined = lines.join("\n")
    assert_match(/Subtasks/, joined)
    assert_match(/Child/, joined)
  end

  def test_build_detail_lines_includes_blockers
    id1 = @db.add_task("Blocked", author: "alice")
    id2 = @db.add_task("Blocker", author: "alice")
    @db.add_blocker(id1, id2)
    task = @db.get_task(id1)
    lines = Pylonite::TUI.build_detail_lines(task, 80)
    joined = lines.join("\n")
    assert_match(/Blocked by/, joined)
    assert_match(/Blocker/, joined)
  end

  def test_build_detail_lines_includes_blocking
    id1 = @db.add_task("Task A", author: "alice")
    id2 = @db.add_task("Task B", author: "alice")
    @db.add_blocker(id2, id1)
    task = @db.get_task(id1)
    lines = Pylonite::TUI.build_detail_lines(task, 80)
    joined = lines.join("\n")
    assert_match(/Blocking/, joined)
  end

  def test_build_detail_lines_includes_parent
    parent = @db.add_task("Parent", author: "alice")
    sub = @db.add_subtask(parent, "Child", author: "alice")
    task = @db.get_task(sub)
    lines = Pylonite::TUI.build_detail_lines(task, 80)
    joined = lines.join("\n")
    assert_match(/Parent/, joined)
  end

  def test_build_detail_lines_shows_no_assignee
    id = @db.add_task("Task", author: "alice")
    task = @db.get_task(id)
    lines = Pylonite::TUI.build_detail_lines(task, 80)
    joined = lines.join("\n")
    assert_match(/\(none\)/, joined)
  end

  def test_build_detail_lines_shows_assignee
    id = @db.add_task("Task", author: "alice", assignee: "bob")
    task = @db.get_task(id)
    lines = Pylonite::TUI.build_detail_lines(task, 80)
    joined = lines.join("\n")
    assert_match(/bob/, joined)
  end

  # --- Board input handling ---

  def test_handle_board_input_quit
    state = { view: :board, col_index: 0, row_index: 0, show_archived: false, db: @db }
    result = Pylonite::TUI.handle_board_input(state, "q")
    assert_equal false, result
  end

  def test_handle_board_input_toggle_archived
    state = { view: :board, col_index: 0, row_index: 0, show_archived: false, db: @db }
    Pylonite::TUI.handle_board_input(state, "a")
    assert state[:show_archived]
    Pylonite::TUI.handle_board_input(state, "a")
    refute state[:show_archived]
  end

  def test_handle_board_input_navigate_right
    @db.add_task("Task", author: "a")
    state = { view: :board, col_index: 0, row_index: 0, show_archived: false, db: @db }
    Pylonite::TUI.handle_board_input(state, :right)
    assert_equal 1, state[:col_index]
  end

  def test_handle_board_input_navigate_left_at_zero
    state = { view: :board, col_index: 0, row_index: 0, show_archived: false, db: @db }
    Pylonite::TUI.handle_board_input(state, :left)
    assert_equal 0, state[:col_index]
  end

  def test_handle_board_input_navigate_right_clamped
    state = { view: :board, col_index: 3, row_index: 0, show_archived: false, db: @db }
    Pylonite::TUI.handle_board_input(state, :right)
    assert_equal 3, state[:col_index] # 4 visible boards (0-3)
  end

  def test_handle_board_input_enter_opens_detail
    @db.add_task("Task", author: "a")
    state = { view: :board, col_index: 0, row_index: 0, show_archived: false, db: @db, detail_task_id: nil, detail_scroll: 0 }
    Pylonite::TUI.handle_board_input(state, "\r")
    assert_equal :detail, state[:view]
    assert_equal 1, state[:detail_task_id]
  end

  def test_handle_board_input_enter_on_empty_stays
    state = { view: :board, col_index: 0, row_index: 0, show_archived: false, db: @db, detail_task_id: nil, detail_scroll: 0 }
    Pylonite::TUI.handle_board_input(state, "\r")
    assert_equal :board, state[:view]
  end

  # --- Detail input handling ---

  def test_handle_detail_input_back
    state = { view: :detail, detail_scroll: 0 }
    Pylonite::TUI.handle_detail_input(state, "b")
    assert_equal :board, state[:view]
  end

  def test_handle_detail_input_quit
    state = { view: :detail, detail_scroll: 0 }
    result = Pylonite::TUI.handle_detail_input(state, "q")
    assert_equal false, result
  end

  def test_handle_detail_input_scroll_down
    state = { view: :detail, detail_scroll: 0 }
    Pylonite::TUI.handle_detail_input(state, :down)
    assert_equal 1, state[:detail_scroll]
  end

  def test_handle_detail_input_scroll_up_clamped
    state = { view: :detail, detail_scroll: 0 }
    Pylonite::TUI.handle_detail_input(state, :up)
    assert_equal 0, state[:detail_scroll]
  end

  def test_handle_detail_input_vim_keys
    state = { view: :detail, detail_scroll: 0 }
    Pylonite::TUI.handle_detail_input(state, "j")
    assert_equal 1, state[:detail_scroll]
    Pylonite::TUI.handle_detail_input(state, "k")
    assert_equal 0, state[:detail_scroll]
  end

  # --- Move functionality ---

  def test_board_m_enters_move_mode
    @db.add_task("Task", author: "a")
    state = { view: :board, col_index: 0, row_index: 0, show_archived: false, db: @db, moving: false, move_task_id: nil }
    Pylonite::TUI.handle_board_input(state, "m")
    assert state[:moving]
    assert_equal 1, state[:move_task_id]
  end

  def test_board_m_on_empty_does_nothing
    state = { view: :board, col_index: 0, row_index: 0, show_archived: false, db: @db, moving: false, move_task_id: nil }
    Pylonite::TUI.handle_board_input(state, "m")
    refute state[:moving]
    assert_nil state[:move_task_id]
  end

  def test_detail_m_enters_move_mode
    state = { view: :detail, detail_scroll: 0, detail_task_id: 42, moving: false, move_task_id: nil }
    Pylonite::TUI.handle_detail_input(state, "m")
    assert state[:moving]
    assert_equal 42, state[:move_task_id]
  end

  def test_move_input_1_moves_to_backlog
    id = @db.add_task("Task", author: "a", board: "todo")
    state = { db: @db, moving: true, move_task_id: id }
    Pylonite::TUI.handle_move_input(state, "1")
    refute state[:moving]
    assert_equal "backlog", @db.get_task(id)["board"]
  end

  def test_move_input_2_moves_to_todo
    id = @db.add_task("Task", author: "a")
    state = { db: @db, moving: true, move_task_id: id }
    Pylonite::TUI.handle_move_input(state, "2")
    assert_equal "todo", @db.get_task(id)["board"]
  end

  def test_move_input_3_moves_to_in_progress
    id = @db.add_task("Task", author: "a")
    state = { db: @db, moving: true, move_task_id: id }
    Pylonite::TUI.handle_move_input(state, "3")
    assert_equal "in_progress", @db.get_task(id)["board"]
  end

  def test_move_input_4_moves_to_done
    id = @db.add_task("Task", author: "a")
    state = { db: @db, moving: true, move_task_id: id }
    Pylonite::TUI.handle_move_input(state, "4")
    assert_equal "done", @db.get_task(id)["board"]
  end

  def test_move_input_5_moves_to_archived
    id = @db.add_task("Task", author: "a")
    state = { db: @db, moving: true, move_task_id: id }
    Pylonite::TUI.handle_move_input(state, "5")
    assert_equal "archived", @db.get_task(id)["board"]
  end

  def test_move_input_cancel
    id = @db.add_task("Task", author: "a")
    state = { db: @db, moving: true, move_task_id: id }
    Pylonite::TUI.handle_move_input(state, "x")
    refute state[:moving]
    assert_nil state[:move_task_id]
    assert_equal "backlog", @db.get_task(id)["board"]
  end

  # --- Help overlay ---

  def test_board_question_mark_shows_help
    state = { view: :board, col_index: 0, row_index: 0, show_archived: false, db: @db, show_help: false }
    Pylonite::TUI.handle_board_input(state, "?")
    assert state[:show_help]
  end

  def test_detail_question_mark_shows_help
    state = { view: :detail, detail_scroll: 0, show_help: false }
    Pylonite::TUI.handle_detail_input(state, "?")
    assert state[:show_help]
  end

  def test_help_overlay_content
    content = Pylonite::TUI.render_help_overlay(80, 24)
    stripped = content.gsub(/\e\[[0-9;]*[A-Za-z]/, "")
    assert_match(/Keyboard Shortcuts/, stripped)
    assert_match(/Board View/, stripped)
    assert_match(/Detail View/, stripped)
    assert_match(/Move Overlay/, stripped)
  end

  def test_move_overlay_content
    id = @db.add_task("My task", author: "a")
    state = { db: @db, move_task_id: id }
    content = Pylonite::TUI.render_move_overlay(state, 80, 24)
    stripped = content.gsub(/\e\[[0-9;]*[A-Za-z]/, "")
    assert_match(/Move task ##{id}/, stripped)
    assert_match(/Backlog/, stripped)
    assert_match(/In Progress/, stripped)
    assert_match(/1-5/, stripped)
  end

  # --- Comment functionality ---

  def test_board_c_on_empty_does_nothing
    state = { view: :board, col_index: 0, row_index: 0, show_archived: false, db: @db, moving: false, move_task_id: nil, show_help: false }
    # 'c' on empty board should not error
    Pylonite::TUI.handle_board_input(state, "c")
    # no crash = pass
  end

  def test_prompt_comment_adds_comment
    id = @db.add_task("Task", author: "a")
    state = { db: @db }

    # Simulate stdin with a comment line
    original_stdin = $stdin
    original_stdout = $stdout
    $stdin = StringIO.new("My TUI comment\n")
    $stdout = StringIO.new
    begin
      Pylonite::TUI.prompt_comment(state, id)
    ensure
      $stdin = original_stdin
      $stdout = original_stdout
    end

    task = @db.get_task(id)
    assert_equal 1, task["comments"].length
    assert_equal "My TUI comment", task["comments"][0]["text"]
  end

  def test_prompt_comment_skips_empty_input
    id = @db.add_task("Task", author: "a")
    state = { db: @db }

    original_stdin = $stdin
    original_stdout = $stdout
    $stdin = StringIO.new("   \n")
    $stdout = StringIO.new
    begin
      Pylonite::TUI.prompt_comment(state, id)
    ensure
      $stdin = original_stdin
      $stdout = original_stdout
    end

    task = @db.get_task(id)
    assert_empty task["comments"]
  end

  def test_help_overlay_mentions_comment
    content = Pylonite::TUI.render_help_overlay(80, 30)
    stripped = content.gsub(/\e\[[0-9;]*[A-Za-z]/, "")
    assert_match(/comment/i, stripped)
  end

  # --- Log view ---

  def test_board_L_switches_to_log
    state = { view: :board, col_index: 0, row_index: 0, show_archived: false, db: @db, moving: false, move_task_id: nil, show_help: false, log_scroll: 0 }
    Pylonite::TUI.handle_board_input(state, "L")
    assert_equal :log, state[:view]
    assert_equal 0, state[:log_scroll]
  end

  def test_log_input_back
    state = { view: :log, log_scroll: 0 }
    Pylonite::TUI.handle_log_input(state, "b")
    assert_equal :board, state[:view]
  end

  def test_log_input_quit
    state = { view: :log, log_scroll: 0 }
    result = Pylonite::TUI.handle_log_input(state, "q")
    assert_equal false, result
  end

  def test_log_input_scroll
    state = { view: :log, log_scroll: 0 }
    Pylonite::TUI.handle_log_input(state, "j")
    assert_equal 1, state[:log_scroll]
    Pylonite::TUI.handle_log_input(state, "k")
    assert_equal 0, state[:log_scroll]
  end

  def test_log_input_scroll_up_clamped
    state = { view: :log, log_scroll: 0 }
    Pylonite::TUI.handle_log_input(state, :up)
    assert_equal 0, state[:log_scroll]
  end

  def test_log_input_help
    state = { view: :log, log_scroll: 0, show_help: false }
    Pylonite::TUI.handle_log_input(state, "?")
    assert state[:show_help]
  end

  def test_build_log_lines_with_entries
    @db.add_task("Task A", author: "alice")
    @db.add_task("Task B", author: "bob")
    @db.move_task(1, "in_progress", actor: "alice")
    entries = @db.activity_log
    lines = Pylonite::TUI.build_log_lines(entries, 80)
    joined = lines.join("\n")
    assert_match(/Task A/, joined)
    assert_match(/Task B/, joined)
    assert_match(/alice/, joined)
    assert_match(/moved/, joined)
  end

  def test_build_log_lines_empty
    lines = Pylonite::TUI.build_log_lines([], 80)
    joined = lines.join("\n")
    assert_match(/No activity/, joined)
  end

  def test_help_overlay_mentions_log
    content = Pylonite::TUI.render_help_overlay(80, 40)
    stripped = content.gsub(/\e\[[0-9;]*[A-Za-z]/, "")
    assert_match(/Log View/, stripped)
  end
end
