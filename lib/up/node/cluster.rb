# backtick_javascript: true
require 'up/node/server'

%x{
  const cluster = require('node:cluster');
  const num_workers = require('node:os').availableParallelism();
}

module Up
  module Node
    class Cluster < Up::Node::Server
      def initialize(app:, host: 'localhost', port: 3000, scheme: 'http', ca_file: nil, cert_file: nil, key_file: nil, workers: nil)
        super(app: app, host: host, port: port, scheme: scheme, ca_file: ca_file, cert_file: cert_file, key_file: key_file)
        @workers = workers || `num_workers`
        @members = []
      end

      def listen
        raise "already running" unless @members.empty?
        %x{
          if (cluster.isPrimary) {
            for (let i = 0; i < #@workers; i++) {
              #@members.push(cluster.fork());
            }
          } else {
            #{super}
          }
        }
      end

      def stop
        if Up::CLI::stoppable?
          @members.each { |m| `m.kill()` } 
          @members.clear
        end
      end
    end
  end
end
