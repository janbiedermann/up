require_relative 'roda_app'
if defined? RubyVM && defined? RubyVM::YJIT
  # ensure up contenders use a JIT
  RubyVM::YJIT.enable
end
run RodaApp.freeze
