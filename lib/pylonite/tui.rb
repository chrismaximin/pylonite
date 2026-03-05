require "io/console"

module Pylonite
  module TUI
    BOARD_COLORS = {
      "backlog" => "\e[37m",
      "todo" => "\e[33m",
      "in_progress" => "\e[36m",
      "done" => "\e[32m",
      "archived" => "\e[90m"
    }.freeze

    BOLD = "\e[1m"
    RESET = "\e[0m"
    REVERSE = "\e[7m"
    DIM = "\e[2m"

    def self.run(project_path = Dir.pwd)
      db = Database.new(project_path)
      state = {
        db: db,
        view: :board,
        col_index: 0,
        row_index: 0,
        show_archived: false,
        detail_task_id: nil,
        detail_scroll: 0,
        show_help: false,
        moving: false,
        move_task_id: nil,
        log_scroll: 0
      }

      setup_terminal
      trap("WINCH") { render(state) }

      begin
        render(state)
        loop do
          break unless handle_input(state)
          render(state)
        end
      ensure
        restore_terminal
        db.close
      end
    end

    def self.setup_terminal
      print "\e[?25l"      # hide cursor
      print "\e[?1049h"    # alternate screen buffer
      $stdout.flush
    end

    def self.restore_terminal
      print "\e[?1049l"    # restore screen buffer
      print "\e[?25h"      # show cursor
      $stdout.flush
    end

    def self.handle_input(state)
      char = read_key
      return true unless char

      if state[:show_help]
        state[:show_help] = false
        return true
      end

      if state[:moving]
        return handle_move_input(state, char)
      end

      case state[:view]
      when :board
        handle_board_input(state, char)
      when :detail
        handle_detail_input(state, char)
      when :log
        handle_log_input(state, char)
      end
    end

    def self.read_key
      $stdin.raw do |io|
        c = io.getc
        return nil unless c

        if c == "\e"
          return "\e" unless IO.select([io], nil, nil, 0.05)
          seq = io.getc
          if seq == "["
            code = io.getc
            case code
            when "A" then return :up
            when "B" then return :down
            when "C" then return :right
            when "D" then return :left
            end
          end
          return "\e"
        end

        c
      end
    end

    def self.handle_board_input(state, key)
      boards = visible_boards(state)
      tasks_by_board = load_board_tasks(state)

      case key
      when "q", "\e"
        return false
      when :up, "k"
        state[:row_index] = [state[:row_index] - 1, 0].max
      when :down, "j"
        col_tasks = tasks_by_board[boards[state[:col_index]]] || []
        max_row = [(col_tasks.length - 1), 0].max
        state[:row_index] = [state[:row_index] + 1, max_row].min
      when :left, "h"
        state[:col_index] = [state[:col_index] - 1, 0].max
        col_tasks = tasks_by_board[boards[state[:col_index]]] || []
        max_row = [(col_tasks.length - 1), 0].max
        state[:row_index] = [state[:row_index], max_row].min
      when :right, "l"
        state[:col_index] = [state[:col_index] + 1, boards.length - 1].min
        col_tasks = tasks_by_board[boards[state[:col_index]]] || []
        max_row = [(col_tasks.length - 1), 0].max
        state[:row_index] = [state[:row_index], max_row].min
        state[:row_index] = 0 if col_tasks.empty?
      when "a"
        state[:show_archived] = !state[:show_archived]
        state[:col_index] = [state[:col_index], visible_boards(state).length - 1].min
      when "\r"
        col_tasks = tasks_by_board[boards[state[:col_index]]] || []
        if col_tasks[state[:row_index]]
          state[:detail_task_id] = col_tasks[state[:row_index]]["id"]
          state[:detail_scroll] = 0
          state[:view] = :detail
        end
      when "m"
        col_tasks = tasks_by_board[boards[state[:col_index]]] || []
        if col_tasks[state[:row_index]]
          state[:moving] = true
          state[:move_task_id] = col_tasks[state[:row_index]]["id"]
        end
      when "c"
        col_tasks = tasks_by_board[boards[state[:col_index]]] || []
        if col_tasks[state[:row_index]]
          prompt_comment(state, col_tasks[state[:row_index]]["id"])
        end
      when "L"
        state[:view] = :log
        state[:log_scroll] = 0
      when "?"
        state[:show_help] = true
      end

      true
    end

    def self.handle_detail_input(state, key)
      case key
      when "q"
        return false
      when "b", "\e"
        state[:view] = :board
      when :up, "k"
        state[:detail_scroll] = [state[:detail_scroll] - 1, 0].max
      when :down, "j"
        state[:detail_scroll] += 1
      when "m"
        state[:moving] = true
        state[:move_task_id] = state[:detail_task_id]
      when "c"
        prompt_comment(state, state[:detail_task_id])
      when "?"
        state[:show_help] = true
      end

      true
    end

    def self.handle_log_input(state, key)
      case key
      when "q"
        return false
      when "b", "\e"
        state[:view] = :board
      when :up, "k"
        state[:log_scroll] = [state[:log_scroll] - 1, 0].max
      when :down, "j"
        state[:log_scroll] += 1
      when "?"
        state[:show_help] = true
      end

      true
    end

    def self.handle_move_input(state, key)
      case key
      when "1" then do_move(state, "backlog")
      when "2" then do_move(state, "todo")
      when "3" then do_move(state, "in_progress")
      when "4" then do_move(state, "done")
      when "5" then do_move(state, "archived")
      else
        state[:moving] = false
        state[:move_task_id] = nil
      end
      true
    end

    def self.do_move(state, board)
      state[:db].move_task(state[:move_task_id], board)
      state[:moving] = false
      state[:move_task_id] = nil
    end

    def self.prompt_comment(state, task_id)
      _, rows = terminal_size
      # Show prompt on the last row
      print "\e[#{rows};1H\e[2K" # move to last row, clear it
      print "#{BOLD}Comment:#{RESET} "
      # Restore normal terminal mode for text input
      print "\e[?25h" # show cursor
      $stdout.flush

      text = nil
      if $stdin.respond_to?(:cooked)
        $stdin.cooked { text = $stdin.gets }
      else
        text = $stdin.gets
      end
      print "\e[?25l" # hide cursor again

      if text && !(text = text.strip).empty?
        state[:db].add_comment(task_id, text)
      end
    end

    def self.visible_boards(state)
      if state[:show_archived]
        Database::BOARDS.dup
      else
        Database::BOARDS.reject { |b| b == "archived" }
      end
    end

    def self.load_board_tasks(state)
      tasks = state[:db].list_tasks(include_archived: state[:show_archived])
      tasks.group_by { |t| t["board"] }
    end

    def self.render(state)
      cols, rows = terminal_size
      buf = +""
      buf << "\e[2J\e[H" # clear screen, cursor home

      case state[:view]
      when :board
        buf << render_board(state, cols, rows)
      when :detail
        buf << render_detail(state, cols, rows)
      when :log
        buf << render_log(state, cols, rows)
      end

      if state[:show_help]
        buf << render_help_overlay(cols, rows)
      elsif state[:moving]
        buf << render_move_overlay(state, cols, rows)
      end

      print buf
      $stdout.flush
    end

    def self.terminal_size
      IO.console.winsize.reverse
    rescue
      [80, 24]
    end

    def self.render_board(state, cols, rows)
      boards = visible_boards(state)
      tasks_by_board = load_board_tasks(state)
      buf = +""

      # Title bar
      title = " PYLONITE - Task Board "
      pad = [(cols - title.length) / 2, 0].max
      buf << "#{REVERSE}#{BOLD}#{' ' * pad}#{title}#{' ' * (cols - pad - title.length)}#{RESET}\n"

      # Column layout
      num_cols = boards.length
      col_width = cols / num_cols
      available_rows = rows - 4 # title + header + status bar + bottom padding

      # Column headers
      boards.each_with_index do |board, i|
        color = BOARD_COLORS[board] || RESET
        label = board_label(board)
        task_count = (tasks_by_board[board] || []).length
        header = " #{label} (#{task_count})"
        header = truncate(header, col_width - 1)
        if i == state[:col_index]
          buf << "#{REVERSE}#{color}#{BOLD}#{header.ljust(col_width)}#{RESET}"
        else
          buf << "#{color}#{BOLD}#{header.ljust(col_width)}#{RESET}"
        end
      end
      buf << "\n"

      # Separator
      boards.each do |_board|
        buf << "#{'─' * col_width}"
      end
      buf << "\n"

      # Task rows
      (0...available_rows).each do |row_i|
        boards.each_with_index do |board, col_i|
          color = BOARD_COLORS[board] || RESET
          col_tasks = tasks_by_board[board] || []
          task = col_tasks[row_i]

          if task
            id_str = "##{task['id']}"
            max_title_len = col_width - id_str.length - 3
            title = truncate(task["title"], [max_title_len, 4].max)
            cell = " #{id_str} #{title}"
            cell = truncate(cell, col_width - 1)

            if col_i == state[:col_index] && row_i == state[:row_index]
              buf << "#{REVERSE}#{color}#{cell.ljust(col_width)}#{RESET}"
            else
              buf << "#{color}#{cell.ljust(col_width)}#{RESET}"
            end
          else
            buf << "#{' ' * col_width}"
          end
        end
        buf << "\n"
      end

      # Status bar
      bar_text = " q:quit  hjkl:navigate  enter:detail  m:move  c:comment  L:log  a:archived  ?:help"
      archived_status = state[:show_archived] ? " [archived:on]" : ""
      bar_text += archived_status
      buf << "\e[#{rows};1H" # move to last row
      buf << "#{REVERSE}#{DIM}#{bar_text.ljust(cols)}#{RESET}"

      buf
    end

    def self.render_detail(state, cols, rows)
      task = state[:db].get_task(state[:detail_task_id])
      return render_board(state, cols, rows) unless task

      lines = build_detail_lines(task, cols)
      buf = +""

      # Title bar
      title = " Task ##{task['id']} - Detail View "
      pad = [(cols - title.length) / 2, 0].max
      buf << "#{REVERSE}#{BOLD}#{' ' * pad}#{title}#{' ' * (cols - pad - title.length)}#{RESET}\n"

      available = rows - 3 # title bar + status bar + padding
      scroll = [state[:detail_scroll], [lines.length - available, 0].max].min
      state[:detail_scroll] = scroll

      visible = lines[scroll, available] || []
      visible.each { |line| buf << "#{line}\n" }

      # Fill remaining lines
      remaining = available - visible.length
      remaining.times { buf << "\n" }

      # Status bar
      bar_text = " b:back  q:quit  j/k:scroll  m:move  c:comment  ?:help"
      buf << "\e[#{rows};1H"
      buf << "#{REVERSE}#{DIM}#{bar_text.ljust(cols)}#{RESET}"

      buf
    end

    def self.render_log(state, cols, rows)
      entries = state[:db].activity_log
      buf = +""

      # Title bar
      title = " PYLONITE - Activity Log "
      pad = [(cols - title.length) / 2, 0].max
      buf << "#{REVERSE}#{BOLD}#{' ' * pad}#{title}#{' ' * (cols - pad - title.length)}#{RESET}\n"

      lines = build_log_lines(entries, cols)
      available = rows - 3

      scroll = [state[:log_scroll], [lines.length - available, 0].max].min
      state[:log_scroll] = scroll

      visible = lines[scroll, available] || []
      visible.each { |line| buf << "#{line}\n" }

      remaining = available - visible.length
      remaining.times { buf << "\n" }

      bar_text = " b:back  q:quit  j/k:scroll  ?:help"
      buf << "\e[#{rows};1H"
      buf << "#{REVERSE}#{DIM}#{bar_text.ljust(cols)}#{RESET}"

      buf
    end

    def self.build_log_lines(entries, cols)
      return ["", "  #{DIM}No activity yet.#{RESET}"] if entries.empty?

      lines = []
      entries.each do |e|
        lines << "  #{DIM}#{e["created_at"]}#{RESET} #{e["actor"]} #{format_log_action(e["action"])} #{BOLD}##{e["task_id"]}#{RESET} #{truncate(e["title"], cols - 40)}"
        lines << "    #{DIM}#{e["detail"]}#{RESET}"
        lines << ""
      end
      lines
    end

    def self.format_log_action(action)
      case action
      when "created" then "created"
      when "moved" then "moved"
      when "assigned" then "assigned"
      when "commented" then "commented on"
      when "updated" then "updated"
      when "blocker_added" then "added blocker to"
      when "blocker_removed" then "removed blocker from"
      when "subtask_added" then "added subtask to"
      when "subtask_created" then "created subtask"
      else action.tr("_", " ")
      end
    end

    def self.render_overlay(lines, cols, rows)
      box_width = lines.map { |l| l.gsub(/\e\[[0-9;]*m/, "").length }.max + 4
      box_width = [box_width, cols - 4].min
      box_height = lines.length + 2
      start_col = [(cols - box_width) / 2, 1].max
      start_row = [(rows - box_height) / 2, 1].max

      buf = +""
      buf << "\e[#{start_row};#{start_col}H"
      buf << "#{REVERSE}#{' ' * box_width}#{RESET}"
      lines.each_with_index do |line, i|
        buf << "\e[#{start_row + 1 + i};#{start_col}H"
        stripped = line.gsub(/\e\[[0-9;]*m/, "")
        padding = box_width - stripped.length - 4
        buf << "#{REVERSE}  #{RESET} #{line}#{' ' * [padding, 0].max} #{REVERSE} #{RESET}"
      end
      buf << "\e[#{start_row + box_height - 1};#{start_col}H"
      buf << "#{REVERSE}#{' ' * box_width}#{RESET}"
      buf
    end

    def self.render_help_overlay(cols, rows)
      lines = [
        "#{BOLD}Keyboard Shortcuts#{RESET}",
        "",
        "#{BOLD}Board View#{RESET}",
        "  h/l, left/right   Switch columns",
        "  j/k, up/down      Move between tasks",
        "  Enter             View task detail",
        "  m                 Move selected task to another board",
        "  c                 Add comment to selected task",
        "  L                 Activity log",
        "  a                 Toggle archived column",
        "  q, Esc            Quit",
        "",
        "#{BOLD}Detail View#{RESET}",
        "  j/k, up/down      Scroll",
        "  m                 Move task to another board",
        "  c                 Add comment",
        "  b, Esc            Back to board view",
        "  q                 Quit",
        "",
        "#{BOLD}Log View#{RESET}",
        "  j/k, up/down      Scroll",
        "  b, Esc            Back to board view",
        "  q                 Quit",
        "",
        "#{BOLD}Move Overlay#{RESET}",
        "  1                 Backlog",
        "  2                 Todo",
        "  3                 In Progress",
        "  4                 Done",
        "  5                 Archived",
        "  Any other key     Cancel",
        "",
        "#{DIM}Press any key to close#{RESET}"
      ]
      render_overlay(lines, cols, rows)
    end

    def self.render_move_overlay(state, cols, rows)
      task = state[:db].get_task(state[:move_task_id])
      title = task ? truncate(task["title"], 30) : "?"
      current = task ? task["board"] : "?"
      lines = [
        "#{BOLD}Move task ##{state[:move_task_id]}#{RESET} #{DIM}#{title}#{RESET}",
        "#{DIM}Currently: #{board_label(current)}#{RESET}",
        "",
        "  #{BOARD_COLORS["backlog"]}1#{RESET}  Backlog",
        "  #{BOARD_COLORS["todo"]}2#{RESET}  Todo",
        "  #{BOARD_COLORS["in_progress"]}3#{RESET}  In Progress",
        "  #{BOARD_COLORS["done"]}4#{RESET}  Done",
        "  #{BOARD_COLORS["archived"]}5#{RESET}  Archived",
        "",
        "#{DIM}Press 1-5 to move, any other key to cancel#{RESET}"
      ]
      render_overlay(lines, cols, rows)
    end

    def self.build_detail_lines(task, cols)
      lines = []
      color = BOARD_COLORS[task["board"]] || RESET

      lines << ""
      lines << "  #{BOLD}#{task['title']}#{RESET}"
      lines << ""
      lines << "  #{DIM}Board:#{RESET}    #{color}#{board_label(task['board'])}#{RESET}"
      lines << "  #{DIM}Author:#{RESET}   #{task['author']}"
      lines << "  #{DIM}Assignee:#{RESET} #{task['assignee'] || '(none)'}"
      lines << "  #{DIM}Created:#{RESET}  #{task['created_at']}"
      lines << "  #{DIM}Updated:#{RESET}  #{task['updated_at']}"

      if task["description"] && !task["description"].empty?
        lines << ""
        lines << "  #{BOLD}Description#{RESET}"
        wrap_text(task["description"], cols - 4).each { |l| lines << "  #{l}" }
      end

      parent = task["parent"]
      if parent
        lines << ""
        lines << "  #{BOLD}Parent#{RESET}"
        lines << "    ##{parent['id']} #{parent['title']}"
      end

      subtasks = task["subtasks"] || []
      unless subtasks.empty?
        lines << ""
        lines << "  #{BOLD}Subtasks#{RESET}"
        subtasks.each do |st|
          st_color = BOARD_COLORS[st["board"]] || RESET
          lines << "    ##{st['id']} #{st_color}[#{board_label(st['board'])}]#{RESET} #{st['title']}"
        end
      end

      blockers = task["blockers"] || []
      unless blockers.empty?
        lines << ""
        lines << "  #{BOLD}Blocked by#{RESET}"
        blockers.each do |b|
          b_color = BOARD_COLORS[b["board"]] || RESET
          lines << "    ##{b['id']} #{b_color}[#{board_label(b['board'])}]#{RESET} #{b['title']}"
        end
      end

      blocked_by_this = task["blocked_by_this"] || []
      unless blocked_by_this.empty?
        lines << ""
        lines << "  #{BOLD}Blocking#{RESET}"
        blocked_by_this.each do |b|
          b_color = BOARD_COLORS[b["board"]] || RESET
          lines << "    ##{b['id']} #{b_color}[#{board_label(b['board'])}]#{RESET} #{b['title']}"
        end
      end

      comments = task["comments"] || []
      unless comments.empty?
        lines << ""
        lines << "  #{BOLD}Comments#{RESET}"
        comments.each do |c|
          lines << ""
          lines << "    #{DIM}#{c['author']} at #{c['created_at']}#{RESET}"
          wrap_text(c["text"], cols - 6).each { |l| lines << "    #{l}" }
        end
      end

      history = task["history"] || []
      unless history.empty?
        lines << ""
        lines << "  #{BOLD}History#{RESET}"
        history.each do |h|
          lines << "    #{DIM}#{h['created_at']}#{RESET} #{h['actor']} - #{h['detail']}"
        end
      end

      lines
    end

    def self.board_label(board)
      board.gsub("_", " ").split.map(&:capitalize).join(" ")
    end

    def self.truncate(str, max)
      return str if str.length <= max
      return str[0, max] if max <= 3
      str[0, max - 3] + "..."
    end

    def self.wrap_text(text, width)
      return [""] if text.nil? || text.empty?
      text.split("\n").flat_map do |paragraph|
        if paragraph.empty?
          [""]
        else
          words = paragraph.split
          lines = []
          current = +""
          words.each do |word|
            if current.empty?
              current = word
            elsif current.length + 1 + word.length <= width
              current << " " << word
            else
              lines << current
              current = +word
            end
          end
          lines << current unless current.empty?
          lines.empty? ? [""] : lines
        end
      end
    end
  end
end
