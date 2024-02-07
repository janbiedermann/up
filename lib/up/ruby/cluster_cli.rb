require 'rack/builder'
require 'up/ruby/rack_cluster'

module Up
  module CLI
    def self.call
      Up::Ruby::RackCluster.run(get_app, get_options)
    end
  end
end
