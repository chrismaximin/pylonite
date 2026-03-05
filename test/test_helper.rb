require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/pylonite"

module Pylonite
  module TestHelper
    def setup_test_db
      @tmpdir = Dir.mktmpdir("pylonite_test")
      @project_path = File.join(@tmpdir, "test_project")
      FileUtils.mkdir_p(@project_path)
      @db = Pylonite::Database.new(@project_path)
      @_test_db_paths = [@db.db_path]
    end

    def track_test_db(project_path)
      @_test_db_paths << Pylonite::Database.db_path_for(project_path)
    end

    def teardown_test_db
      @db&.close
      (@_test_db_paths || []).each do |p|
        FileUtils.rm_f(p)
        FileUtils.rm_f("#{p}-wal")
        FileUtils.rm_f("#{p}-shm")
      end
      FileUtils.rm_rf(@tmpdir) if @tmpdir
    end
  end
end
