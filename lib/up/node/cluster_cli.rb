require 'up/node/rack_cluster'

module Up
  module CLI
    def self.call
      Up::Node::RackCluster.run(get_app, get_options)
    end
  end
end
