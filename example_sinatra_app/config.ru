require_relative 'sinatra_app'
if defined? RubyVM
  # ensure up contenders use a JIT
  RubyVM::YJIT.enable
end
run SinatraApp
