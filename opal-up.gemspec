lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require_relative 'lib/up/version'

Gem::Specification.new do |spec|
  spec.name          = 'opal-up'
  spec.version       = Up::VERSION
  spec.authors       = ['Jan Biedermann']
  spec.email         = ['jan@kursator.de']

  spec.summary       = 'Rack server for Opal'
  spec.description   = 'High performance Rack server for Opal Ruby'
  spec.homepage      = ''
  spec.license       = 'MIT'
  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test_app|test|spec|features)/}) }
  spec.bindir        = 'bin'
  spec.executables   = %w[up up_bun]
  spec.require_paths = %w[lib]

  spec.add_dependency 'logger', '~> 1.6.0'
  spec.add_dependency 'opal', '>= 1.8.2', '< 3.0.0'
  spec.add_dependency 'rack', '~> 3.0.9'
  spec.add_dependency 'rackup', '>= 0.2.2', '< 3.0.0'

  spec.add_development_dependency 'rake', '~> 13.1.0'
  spec.add_development_dependency 'rspec', '~> 3.12.0'
end
