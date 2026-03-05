require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/pylonite"

# Point all test databases to a temp directory
TEST_DB_DIR = Dir.mktmpdir("pylonite_test_dbs")
Pylonite::Database.db_dir = TEST_DB_DIR

Minitest.after_run do
  FileUtils.rm_rf(TEST_DB_DIR)
end

module Pylonite
  module TestHelper
    def setup_test_db
      @tmpdir = Dir.mktmpdir("pylonite_test")
      @project_path = File.join(@tmpdir, "test_project")
      FileUtils.mkdir_p(@project_path)
      @db = Pylonite::Database.new(@project_path)
    end

    def teardown_test_db
      @db&.close
      FileUtils.rm_rf(@tmpdir) if @tmpdir
    end
  end
end
