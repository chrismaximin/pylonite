require_relative "lib/pylonite/version"

Gem::Specification.new do |spec|
  spec.name          = "pylonite"
  spec.version       = Pylonite::VERSION
  spec.authors       = ["pylonite contributors"]
  spec.summary       = "SQLite-backed kanban board for agents and humans"
  spec.description   = "A simple, local kanban board backed by SQLite. Designed for AI agents and humans to manage tasks, track progress, and collaborate via CLI and TUI."
  spec.homepage      = "https://github.com/chrismaximin/pylonite"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files         = Dir["lib/**/*.rb", "bin/*", "*.gemspec"]
  spec.bindir        = "bin"
  spec.executables   = ["pylonite"]

  spec.add_dependency "sqlite3", "~> 2.0"

  spec.metadata["homepage_uri"] = spec.homepage
end
