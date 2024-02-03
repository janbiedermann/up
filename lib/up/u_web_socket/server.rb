# backtick_javascript: true
require 'up/cli'
require 'up/u_web_socket/rack_env'

%x{
  module.paths.push(process.cwd() + '/node_modules');
  const uws = require('uWebSockets.js');
}

module Up
  module UWebSocket
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
        self.handle_headers = function(rack_headers, uws_res) {
          if (rack_headers.$$is_hash) {
            var header, k, v;
            for(header of rack_headers) {
              k = header[0];
              if (!k.startsWith('rack.')) {
                v = header[1];
                if (v.$$is_array) {
                  v = v.join("\n");
                }
                uws_res.writeHeader(k, v);
              }
            }
          }
        }

        self.handle_response = function(parts, uws_res) {
          if (parts["$respond_to?"]('each')) {
            #{`parts`.each { |part| `uws_res.write(part)` }}
          } else if (parts["$respond_to?"]('call')) {
            uws_res.write(parts.$call());
          }
          #{`parts`.close if `parts`.respond_to?(:close)}
        }
      }

      def listen
        raise "already running" if @server
        %x{
          const ouwr = Opal.Up.UWebSocket.RackEnv;
          const ouws = Opal.Up.UWebSocket.Server;
          if (#@scheme == 'https') {
            #@server = uws.SSLApp({ ca_file_name: #@ca_file, cert_file_name: #@cert_file, key_file_name: #@key_file });
          } else {
            #@server = uws.App();
          }
          #@server.any('/*', (res, req) => {
            const rack_res = #@app.$call(ouwr.$new(req, #@config));
            res.writeStatus(`${rack_res[0].toString()} OK`);
            ouws.handle_headers(rack_res[1], res);
            ouws.handle_response(rack_res[2], res);
            res.end();
          });
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
