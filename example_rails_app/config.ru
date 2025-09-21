# This file is used by Rack-based servers to start the application.
if defined?(RubyVM) && defined?(RubyVM::YJIT)
  # ensure up contenders use a JIT
  RubyVM::YJIT.enable
end

require_relative "config/environment"

run Rails.application
Rails.application.load_server
