require_relative 'rack_app'
if defined?(RubyVM) && defined?(RubyVM::YJIT)
  # ensure up contenders use a JIT
  RubyVM::YJIT.enable
end

require 'rack/lint'
use Rack::Lint

run RackApp
