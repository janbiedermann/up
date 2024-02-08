# backtick_javascript: true
require 'logger'
require 'up/cli'

%x{
  module.paths.push(process.cwd() + '/node_modules');
  const http = require('node:http');
  const https = require('node:https');
  const fs = require('node:fs');
}

module Up
  module Node
    class Server
      def initialize(app:, host: 'localhost', port: 3000, scheme: 'http', ca_file: nil, cert_file: nil, key_file: nil, logger: Logger.new(STDERR))
        @app = app
        @scheme    = scheme || 'http'
        raise "unsupported scheme #{@scheme}" unless %w[http https].include?(@scheme)
        @host      = host || 'localhost'
        @port      = port&.to_i || 3000
        @config    = { handler: self.class.name, engine: "node/#{`process.version`}", port: port, scheme: scheme, host: host, logger: logger }.freeze
        @ca_file   = ca_file
        @cert_file = cert_file
        @key_file  = key_file
        @default_input = IO.new
        @server    = nil
        @logger    = logger
        @t_factory = proc { |filename, _content_type| File.new(filename, 'a+') }
      end

      %x{
        self.handle_headers = function(rack_headers, srv_res) {
          if (rack_headers.$$is_hash) {
            var header, v;
            for(header of rack_headers) {
              v = header[1];
              if (v.$$is_array) {
                v = v.join("\n");
              }
              srv_res.setHeader(header[0], v);
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
          const ouns = Opal.Up.Node.Server;
          function handler(req, res) {
            const env = new Map();
            env.set('rack.errors',#{STDERR});
            env.set('rack.input', #@default_input);
            env.set('rack.logger', #@logger);
            env.set('rack.multipart.buffer_size', 4096);
            env.set('rack.multipart.tempfile_factory', #@t_factory);
            env.set('rack.url_scheme', #@scheme);
            env.set('SCRIPT_NAME', "");
            env.set('SERVER_PROTOCOL', req.httpVersion);
            env.set('HTTP_VERSION', req.httpVersion);
            env.set('SERVER_NAME', #@host);
            env.set('SERVER_PORT', #@port);
            env.set('QUERY_STRING', "");
            env.set('REQUEST_METHOD', req.method);
            env.set('PATH_INFO', req.url);
            var hdr, hds = req.headers;
            for (hdr in hds) { env.set('HTTP_' + hdr.toUpperCase().replaceAll('-', '_'), hds[hdr]); }
            const rack_res = #@app.$call(env);
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
