require 'rack/builder'
require 'up/ruby/rack_server'

module Up
  module CLI
    def self.call
      Up::Ruby::RackServer.run(get_app, get_options)
    end
  end
end
