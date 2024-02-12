lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require_relative 'lib/up/version'

Gem::Specification.new do |spec|
  spec.name          = 'opal-up'
  spec.version       = Up::VERSION
  spec.authors       = ['Jan Biedermann']
  spec.email         = ['jan@kursator.de']

  spec.summary       = 'Rack server for Opal'
  spec.description   = 'High performance Rack server for Opal and Ruby'
  spec.homepage      = ''
  spec.license       = 'MIT'
  spec.files         = `git ls-files -- bin ext lib LICENSE README.md`.split("\n")
  spec.bindir        = 'bin'
  spec.executables   = %w[up up_bun up_cluster up_ruby up_ruby_cluster]
  spec.require_paths = %w[lib]
  spec.extensions    = %w[ext/up_ext/extconf.rb]
  spec.required_ruby_version = '>= 3.0.0'

  spec.add_dependency 'logger', '~> 1.6.0'
  spec.add_dependency 'opal', '>= 1.8.2', '< 3.0.0'
  spec.add_dependency 'rack', '~> 3.0.9'
  spec.add_dependency 'rackup', '>= 0.2.2', '< 3.0.0'

  spec.add_development_dependency 'rake', '~> 13.1.0'
  spec.add_development_dependency 'rake-compiler', '~> 1.2.7'
  spec.add_development_dependency 'rspec', '~> 3.12.0'
end
