require 'opal/platform'
require 'nodejs/file'
require 'nodejs/require'
require 'opal-parser'
require 'rack/builder'
require 'up/rack_builder_patch'
require 'up/node/rack_cluster'

module Up
  module CLI
    def self.call
      Up::Node::RackCluster.run(get_app, get_options)
    end
  end
end
