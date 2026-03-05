module Pylonite
  module CLI
    BOARD_COLORS = {
      "backlog" => "\e[37m",
      "todo" => "\e[33m",
      "in_progress" => "\e[36m",
      "done" => "\e[32m",
      "archived" => "\e[90m"
    }.freeze

    RESET = "\e[0m"
    BOLD = "\e[1m"
    DIM = "\e[2m"

    def self.run(args)
      command = args.shift
      case command
      when "add" then cmd_add(args)
      when "show" then cmd_show(args)
      when "list" then cmd_list(args)
      when "move" then cmd_move(args)
      when "comment" then cmd_comment(args)
      when "search" then cmd_search(args)
      when "archive" then cmd_archive(args)
      when "assign" then cmd_assign(args)
      when "block" then cmd_block(args)
      when "unblock" then cmd_unblock(args)
      when "subtask" then cmd_subtask(args)
      when "edit" then cmd_edit(args)
      when "log" then cmd_log(args)
      when "internal" then cmd_internal(args)
      when "tui" then Pylonite::TUI.run
      when "help", "--help", "-h", nil then Pylonite::Help.display
      else
        error("Unknown command: #{command}. Run 'pylonite help' for usage.")
      end
    rescue => e
      error(e.message)
    end

    # --- Commands ---

    def self.cmd_add(args)
      board = extract_option(args, "--board") || "backlog"
      assignee = extract_option(args, "--assign")
      description = extract_option(args, "--description") || extract_option(args, "-d")
      title = args.first
      error("Usage: pylonite add \"task title\" [--board BOARD] [--assign USER] [--description TEXT]") unless title

      db = Database.new
      id = db.add_task(title, board: board, assignee: assignee, description: description)
      puts "Created task #{BOLD}##{id}#{RESET} in #{colorize_board(board)}"
    end

    def self.cmd_show(args)
      id = args.first&.to_i
      error("Usage: pylonite show ID") unless id && id > 0

      db = Database.new
      task = db.get_task(id)
      error("Task ##{id} not found") unless task

      board = task["board"]
      puts "#{BOLD}##{task["id"]}#{RESET} #{task["title"]}"
      puts "  Board:    #{colorize_board(board)}"
      puts "  Author:   #{task["author"]}" if task["author"]
      puts "  Assignee: #{task["assignee"]}" if task["assignee"]
      puts "  Created:  #{task["created_at"]}"
      puts "  Updated:  #{task["updated_at"]}"

      if task["parent"]
        puts "  Parent:   ##{task["parent"]["id"]} #{task["parent"]["title"]}"
      end

      if task["description"] && !task["description"].empty?
        puts ""
        puts "  #{DIM}Description:#{RESET}"
        task["description"].each_line { |l| puts "    #{l.rstrip}" }
      end

      if task["blockers"] && !task["blockers"].empty?
        puts ""
        puts "  #{DIM}Blocked by:#{RESET}"
        task["blockers"].each do |b|
          puts "    ##{b["id"]} #{b["title"]} [#{b["board"]}]"
        end
      end

      if task["blocked_by_this"] && !task["blocked_by_this"].empty?
        puts ""
        puts "  #{DIM}Blocking:#{RESET}"
        task["blocked_by_this"].each do |b|
          puts "    ##{b["id"]} #{b["title"]} [#{b["board"]}]"
        end
      end

      if task["subtasks"] && !task["subtasks"].empty?
        puts ""
        puts "  #{DIM}Subtasks:#{RESET}"
        task["subtasks"].each do |s|
          puts "    ##{s["id"]} #{s["title"]} [#{s["board"]}]"
        end
      end

      if task["comments"] && !task["comments"].empty?
        puts ""
        puts "  #{DIM}Comments:#{RESET}"
        task["comments"].each do |c|
          puts "    #{DIM}#{c["created_at"]} #{c["author"]}:#{RESET} #{c["text"]}"
        end
      end

      if task["history"] && !task["history"].empty?
        puts ""
        puts "  #{DIM}History:#{RESET}"
        task["history"].each do |h|
          puts "    #{DIM}#{h["created_at"]}#{RESET} #{h["actor"]}: #{h["detail"]}"
        end
      end
    end

    def self.cmd_list(args)
      board = extract_option(args, "--board")
      include_all = args.delete("--all")

      db = Database.new
      tasks = db.list_tasks(board: board, include_archived: !!include_all)

      if tasks.empty?
        puts "No tasks found."
        return
      end

      grouped = tasks.group_by { |t| t["board"] }
      board_order = Database::BOARDS

      board_order.each do |b|
        next unless grouped[b]
        color = BOARD_COLORS[b] || ""
        puts "#{color}#{BOLD}#{b.upcase.tr("_", " ")}#{RESET}"
        grouped[b].each do |t|
          assignee_str = t["assignee"] ? " #{DIM}(#{t["assignee"]})#{RESET}" : ""
          puts "  #{color}##{t["id"]}#{RESET} #{t["title"]}#{assignee_str}"
        end
        puts ""
      end
    end

    def self.cmd_move(args)
      id = args.shift&.to_i
      board = args.shift
      error("Usage: pylonite move ID BOARD") unless id && id > 0 && board

      db = Database.new
      db.move_task(id, board)
      puts "Moved task #{BOLD}##{id}#{RESET} to #{colorize_board(board)}"
    end

    def self.cmd_comment(args)
      id = args.shift&.to_i
      text = args.first
      error("Usage: pylonite comment ID \"comment text\"") unless id && id > 0 && text

      db = Database.new
      db.add_comment(id, text)
      puts "Comment added to task #{BOLD}##{id}#{RESET}"
    end

    def self.cmd_search(args)
      query = args.first
      error("Usage: pylonite search \"query\"") unless query

      db = Database.new
      tasks = db.search_tasks(query)

      if tasks.empty?
        puts "No tasks matching \"#{query}\"."
        return
      end

      tasks.each do |t|
        color = BOARD_COLORS[t["board"]] || ""
        assignee_str = t["assignee"] ? " #{DIM}(#{t["assignee"]})#{RESET}" : ""
        puts "#{color}##{t["id"]}#{RESET} #{t["title"]} [#{t["board"]}]#{assignee_str}"
      end
    end

    def self.cmd_archive(args)
      id = args.first&.to_i
      error("Usage: pylonite archive ID") unless id && id > 0

      db = Database.new
      db.archive_task(id)
      puts "Archived task #{BOLD}##{id}#{RESET}"
    end

    def self.cmd_assign(args)
      id = args.shift&.to_i
      user = args.first
      error("Usage: pylonite assign ID USER") unless id && id > 0 && user

      db = Database.new
      db.assign_task(id, user)
      puts "Assigned task #{BOLD}##{id}#{RESET} to #{user}"
    end

    def self.cmd_block(args)
      id = args.shift&.to_i
      blocker_id = args.first&.to_i
      error("Usage: pylonite block ID BLOCKER_ID") unless id && id > 0 && blocker_id && blocker_id > 0

      db = Database.new
      db.add_blocker(id, blocker_id)
      puts "Task #{BOLD}##{blocker_id}#{RESET} now blocks #{BOLD}##{id}#{RESET}"
    end

    def self.cmd_unblock(args)
      id = args.shift&.to_i
      blocker_id = args.first&.to_i
      error("Usage: pylonite unblock ID BLOCKER_ID") unless id && id > 0 && blocker_id && blocker_id > 0

      db = Database.new
      db.remove_blocker(id, blocker_id)
      puts "Removed blocker #{BOLD}##{blocker_id}#{RESET} from #{BOLD}##{id}#{RESET}"
    end

    def self.cmd_subtask(args)
      parent_id = args.shift&.to_i
      title = args.first
      error("Usage: pylonite subtask PARENT_ID \"title\"") unless parent_id && parent_id > 0 && title

      db = Database.new
      id = db.add_subtask(parent_id, title)
      puts "Created subtask #{BOLD}##{id}#{RESET} under #{BOLD}##{parent_id}#{RESET}"
    end

    def self.cmd_edit(args)
      id = args.shift&.to_i
      error("Usage: pylonite edit ID [--title \"new title\"] [--description \"new desc\"]") unless id && id > 0

      title = extract_option(args, "--title")
      description = extract_option(args, "--description") || extract_option(args, "-d")
      error("Nothing to update. Use --title or --description / -d") unless title || description

      db = Database.new
      db.update_task(id, title: title, description: description)
      puts "Updated task #{BOLD}##{id}#{RESET}"
    end

    def self.cmd_log(args)
      db = Database.new
      entries = db.activity_log

      if entries.empty?
        puts "No activity yet."
        return
      end

      output = entries.map do |e|
        "#{DIM}#{e["created_at"]}#{RESET} #{e["actor"]} #{format_action(e["action"])} #{BOLD}##{e["task_id"]}#{RESET} #{e["title"]}\n    #{DIM}#{e["detail"]}#{RESET}"
      end.join("\n\n") + "\n"

      if $stdout.tty?
        pager = ENV["PAGER"] || "less -R"
        IO.popen(pager, "w") { |io| io.write(output) }
      else
        $stdout.write(output)
      end
    rescue Errno::EPIPE
      # user quit pager early
    end

    def self.format_action(action)
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

    def self.cmd_internal(args)
      subcommand = args.shift
      case subcommand
      when "appropriate"
        old_path = args.first
        error("Usage: pylonite internal appropriate OLD_DB_PATH") unless old_path
        new_path = Database.appropriate(Dir.pwd, old_path)
        puts "Database moved to #{new_path}"
      else
        error("Unknown internal command: #{subcommand}")
      end
    end

    # --- Helpers ---

    def self.extract_option(args, flag)
      idx = args.index(flag)
      return nil unless idx
      args.delete_at(idx)
      args.delete_at(idx)
    end

    def self.colorize_board(board)
      color = BOARD_COLORS[board] || ""
      "#{color}#{board}#{RESET}"
    end

    def self.error(message)
      $stderr.puts "Error: #{message}"
      exit(1)
    end

    private_class_method :extract_option, :colorize_board, :error, :format_action,
      :cmd_add, :cmd_show, :cmd_list, :cmd_move, :cmd_comment,
      :cmd_search, :cmd_archive, :cmd_assign, :cmd_block, :cmd_unblock,
      :cmd_subtask, :cmd_edit, :cmd_log, :cmd_internal
  end
end
