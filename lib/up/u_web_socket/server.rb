# backtick_javascript: true
require 'logger'
require 'up/cli'

%x{
  module.paths.push(process.cwd() + '/node_modules');
  const uws = require('uWebSockets.js');
}

module Up
  module UWebSocket
    class Server
      def initialize(app:, host: 'localhost', port: 3000, scheme: 'http', ca_file: nil, cert_file: nil, key_file: nil, logger: Logger.new(STDERR))
        @app = app
        @scheme    = scheme || 'http'
        raise "unsupported scheme #{@scheme}" unless %w[http https].include?(@scheme)
        @host      = host || 'localhost'
        @port      = port&.to_i || 3000
        @config    = { handler: self.class.name, engine: "node/#{`process.version`}" }.freeze
        @ca_file   = ca_file
        @cert_file = cert_file
        @key_file  = key_file
        @default_input = IO.new
        @server    = nil
        @logger    = logger
        @t_factory = proc { |filename, _content_type| File.new(filename, 'a+') }
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
          const ouws = Opal.Up.UWebSocket.Server;
          if (#@scheme == 'https') {
            #@server = uws.SSLApp({ ca_file_name: #@ca_file, cert_file_name: #@cert_file, key_file_name: #@key_file });
          } else {
            #@server = uws.App();
          }
          #@server.any('/*', (res, req) => {
            const env = new Map();
            env.set('rack.errors',#{STDERR});
            env.set('rack.input', #@default_input);
            env.set('rack.logger', #@logger);
            env.set('rack.multipart.buffer_size', 4096);
            env.set('rack.multipart.tempfile_factory', #@t_factory);
            env.set('rack.url_scheme', #@scheme);
            env.set('SCRIPT_NAME', "");
            env.set('SERVER_PROTOCOL', 'HTTP/1.1');
            env.set('HTTP_VERSION', 'HTTP/1.1');
            env.set('SERVER_NAME', #@host);
            env.set('SERVER_PORT', #@port);
            env.set('QUERY_STRING', req.getQuery());
            env.set('REQUEST_METHOD', req.getMethod().toUpperCase());
            env.set('PATH_INFO', req.getUrl());
            req.forEach((k, v) => { env.set('HTTP_' + k.toUpperCase().replaceAll('-', '_'), v) });
            const rack_res = #@app.$call(env);
            res.writeStatus(rack_res[0].toString() + ' OK');
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
