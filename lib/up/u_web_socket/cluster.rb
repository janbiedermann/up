# backtick_javascript: true
require 'up/u_web_socket/server'

%x{
  const process = require('node:process');
  const cluster = require('node:cluster');
  const num_workers = require('node:os').availableParallelism();
}

module Up
  module UWebSocket
    class Cluster < Up::UWebSocket::Server
      def initialize(app:, host: 'localhost', port: 3000, scheme: 'http', ca_file: nil, cert_file: nil, key_file: nil, logger: Logger.new(STDERR), workers: nil)
        super(app: app, host: host, port: port, scheme: scheme, ca_file: ca_file, cert_file: cert_file, key_file: key_file, logger: logger)
        @workers = workers || `num_workers`
        @members = []
      end

      def listen
        raise "already running" unless @members.empty?
        %x{
          if (cluster.isPrimary) {
            cluster.on('message', (worker, message, handle) => {
              if (message.c && message.m) {
                for (let member of #@members) {
                  if (member !== worker) {
                    member.send(message);
                  }
                }
              }
            });
            for (let i = 0; i < #@workers; i++) {
              #@members[i] = cluster.fork();
            }
          } else {
            self.worker = true;
            function process_message_handler(message, handle) {
              self.server.publish(message.c, message.m);
            }
            process.on('message', process_message_handler);
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
