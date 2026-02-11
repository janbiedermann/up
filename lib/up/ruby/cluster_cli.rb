require 'rack/builder'
require 'up/ruby/rack_cluster'

module Up
  module CLI
    def self.call
      if RUBY_PLATFORM =~ /mingw/
        Up::Ruby::RackServer.run(get_app, get_options)
      else
        Up::Ruby::RackCluster.run(get_app, get_options)
      end
    end
  end
end
