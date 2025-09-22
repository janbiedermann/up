require_relative 'roda_app'

if RUBY_ENGINE == 'ruby'
  # ensure up! contenders use a JIT
  if defined?(RubyVM::ZJIT)
    RubyVM::ZJIT.enable
  else
    RubyVM::YJIT.enable
  end
end

run RodaApp.freeze
