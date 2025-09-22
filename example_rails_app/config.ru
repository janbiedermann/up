# This file is used by Rack-based servers to start the application.
if RUBY_ENGINE == 'ruby'
  # ensure up! contenders use a JIT
  if defined?(RubyVM::ZJIT)
    RubyVM::ZJIT.enable
  else
    RubyVM::YJIT.enable
  end
end

require_relative "config/environment"

run Rails.application
Rails.application.load_server
