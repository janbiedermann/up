require 'opal/platform'
require 'bun/file'
require 'nodejs/require'
require 'opal-parser'
require 'rack/builder'
require 'up/rack_builder_patch'
require 'up/bun/rack_server'

module Up
  module CLI
    def self.call
      Up::Bun::RackServer.run(get_app, get_options)
    end
  end
end
