# backtick_javascript: true
require 'up/cli'
require 'up/node/rack_env'

%x{
  module.paths.push(process.cwd() + '/node_modules');
  const http = require('node:http');
  const https = require('node:https');
  const fs = require('node:fs');
}

module Up
  module Node
    class Server
      def initialize(app:, host: 'localhost', port: 3000, scheme: 'http', ca_file: nil, cert_file: nil, key_file: nil)
        @app = app
        @scheme    = scheme || 'http'
        raise "unsupported scheme #{@scheme}" unless %w[http https].include?(@scheme)
        @host      = host || 'localhost'
        @port      = port&.to_i || 3000
        @config    = { handler: self.class.name, engine: "node/#{`process.version`}", port: port, scheme: scheme, host: host }.freeze
        @ca_file   = ca_file
        @cert_file = cert_file
        @key_file  = key_file
        @server = nil
      end

      %x{
        self.handle_headers = function(rack_headers, srv_res) {
          if (rack_headers.$$is_hash) {
            var header, k, v;
            for(header of rack_headers) {
              k = header[0];
              if (!k.startsWith('rack.')) {
                v = header[1];
                if (v.$$is_array) {
                  v = v.join("\n");
                }
                srv_res.setHeader(k, v);
              }
            }
          }
        }

        self.handle_response = function(parts, srv_res) {
          if (parts["$respond_to?"]('each')) {
            #{`parts`.each { |part| `srv_res.write(part)` }}
          } else if (parts["$respond_to?"]('call')) {
            srv_res.write(parts.$call());
          }
          #{`parts`.close if `parts`.respond_to?(:close)}
        }
      }

      def listen
        raise "already running" if @server
        %x{
          const ounr = Opal.Up.Node.RackEnv;
          const ouns = Opal.Up.Node.Server;
          function handler(req, res) {
            const rack_res = #@app.$call(ounr.$new(req, #@config));
            res.statusCode = rack_res[0];
            ouns.handle_headers(rack_res[1], res);
            ouns.handle_response(rack_res[2], res);
            res.end();
          }
          if (#@scheme == 'https') {
            #@server = https.createServer({ ca: fs.readFileSync(#@ca_file), cert: fs.readFileSync(#@cert_file), key: fs.readFileSync(#@key_file) }, handler);
          } else {
            #@server = http.createServer(handler);
          }
          #@server.listen(#@port, #@host, () => { console.log(`Server is running on ${#@scheme}://${#@host}:${#@port}`)});
        }
      end

      def stop
        if Up::CLI::stoppable?
          `#@server.close()`
          @server = nil
        end
      end
    end
  end
end
