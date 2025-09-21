# backtick_javascript: true
require 'logger'
require 'stringio'
require 'up/cli'
require 'up/client'

%x{
  const process = require('node:process');
  module.paths.push(process.cwd() + '/node_modules');
  const uws = require('uWebSockets.js');
}

module Up
  class << self
    def publish(channel, message)
      raise 'no instance running' unless @instance
      @instance.publish(channel, message)
    end
  end

  module UWebSocket
    class Server
      def initialize(app:, host: 'localhost', port: 3000, scheme: 'http',
                     ca_file: nil, cert_file: nil, key_file: nil,
                     pid_file: nil, logger: Logger.new(STDERR))
        @app = app
        %x{
          // If app is a promise, the resolution must happen before the handler below is called
          if (#@app instanceof Promise) {
            #@app.then(function (val) { #@app = val; });
          }
        }
        @scheme    = scheme || 'http'
        raise "unsupported scheme #{@scheme}" unless %w[http https].include?(@scheme)
        @host      = host || 'localhost'
        @port      = port&.to_i || 3000
        @port_s    = @port.to_s
        @config    = {
                      handler: self.class.name,
                      engine: "node/#{`process.version`}",
                      port: port,
                      scheme: scheme,
                      host: host,
                      logger: logger
                     }.freeze
        @ca_file   = ca_file
        @cert_file = cert_file
        @key_file  = key_file
        if (@scheme == 'https' || @scheme == 'http2') && (@key_file.nil? || @cert_file.nil?)
          raise "for https :key_file and :cert_file args must be given"
        end
        @pid_file  = pid_file
        @server    = nil
        @logger    = logger
        @t_factory = proc { |filename, _content_type| File.new(filename, 'a+') }
      end

      %x{
        function handle_headers(rack_headers, uws_res) {
          if (rack_headers.$$is_hash) {
            var header, v;
            for(header of rack_headers) {
              v = header[1];
              if (v.$$is_array) {
                v = v.join("\n");
              }
              uws_res.writeHeader(header[0].toLowerCase(), v);
            }
          }
        }

        function handle_response(parts, uws_res) {
          if (parts.$$is_array) {
            let i = 0, l = parts.length, part;
            for (; i < l; i++) {
              part = parts[i];
              uws_res.write(typeof part === "object" && part.$$is_string ? part.toString() : part);
            }
          } else {
            if (parts.$each && parts["$respond_to?"]('each')) {
              #{`parts`.each { |part| `uws_res.write(typeof part === "object" && part.$$is_string ? part.toString() : part)` }}
            } else if (parts.$call && parts["$respond_to?"]('call')) {
              let part = parts.$call();
              uws_res.write(typeof part === "object" && part.$$is_string ? part.toString() : part);
            }
            if (parts.$close && parts["$respond_to?"]('close')) {
              parts.$close();
            }
          }
        }

        const err = #{STDERR};
        function prepare_env(req, ins) {
          const env = new Map()
            .set('rack.errors', err)
            .set('rack.logger', ins.logger)
            .set('rack.multipart.buffer_size', 4096)
            .set('rack.multipart.tempfile_factory', ins.t_factory)
            .set('rack.url_scheme', ins.scheme)
            .set('SCRIPT_NAME', '')
            .set('SERVER_PROTOCOL', 'HTTP/1.1')
            .set('SERVER_NAME', ins.host)
            .set('SERVER_PORT', ins.port_s)
            .set('QUERY_STRING', req.getQuery() || '')
            .set('REQUEST_METHOD', req.getMethod().toUpperCase())
            .set('PATH_INFO', req.getUrl());
          let hdr;
          req.forEach((k, v) => {
            hdr = k.toUpperCase().replaceAll('-', '_');
            if (hdr[0] === 'C' && (hdr === 'CONTENT_TYPE' || hdr === 'CONTENT_LENGTH')) {
              env.set(hdr, v);
            } else {
              env.set('HTTP_' + hdr, v);
            }
          });
          return env;
        }
      }

      def listen
        raise "already running" if @server
        ::Up.instance_variable_set(:@instance, self)
        ::File.write(@pid_file, `process.pid.toString()`) if @pid_file
        puts "Server PID: #{`process.pid`}"
        %x{
          const ouws = Opal.Up.UWebSocket.Server;
          const ouwc = Opal.Up.Client;
          const deco = new TextDecoder();
          if (#@scheme == 'https') {
            #@server = uws.SSLApp({ ca_file_name: #@ca_file, cert_file_name: #@cert_file, key_file_name: #@key_file });
          } else {
            #@server = uws.App();
          }
          #@server.post('/*', (res, req) => {
            const env = prepare_env(req, self);
            let buffer = Buffer.from('');
            res.onData((chunk, is_last) => {
              buffer = Buffer.concat([buffer, Buffer.from(chunk)]);
              if (is_last === true) {
                env.set('rack.input', #{StringIO.new(`buffer.toString()`)});
                const rack_res = #@app.$call(env);
                res.writeStatus(rack_res[0].toString() + ' OK');
                handle_headers(rack_res[1], res);
                handle_response(rack_res[2], res);
                res.end();
              }
            });
            res.onAborted(() => {});
          });
          #@server.any('/*', (res, req) => {
            const rack_res = #@app.$call(prepare_env(req, self));
            res.writeStatus(rack_res[0].toString() + ' OK');
            handle_headers(rack_res[1], res);
            handle_response(rack_res[2], res);
            res.end();
          });
          #@server.ws('/*', {
            close: (ws, code, message) => {
              const user_data = ws.getUserData();
              if (typeof(user_data.client.handler.$on_close) === 'function') {
                user_data.client.ws = ws;
                user_data.client.open = false;
                user_data.client.handler.$on_close(user_data.client);
                user_data.client.ws = null;
              }
            },
            drain: (ws) => {
              const user_data = ws.getUserData();
              if (typeof(user_data.client.handler.$on_drained) === 'function') {
                user_data.client.ws = ws;
                user_data.client.handler.$on_drained(user_data.client);
                user_data.client.ws = null;
              }
            },
            message: (ws, message, isBinary) => {
              const user_data = ws.getUserData();
              if (typeof(user_data.client.handler.$on_message) === 'function') {
                const msg = deco.decode(message);
                user_data.client.ws = ws;
                user_data.client.handler.$on_message(user_data.client, msg);
                user_data.client.ws = null;
              }
            },
            open: (ws) => {
              const user_data = ws.getUserData();
              if (typeof(user_data.client.handler.$on_open) === 'function') {
                user_data.client.ws = ws;
                user_data.client.open = true;
                user_data.client.handler.$on_open(user_data.client);
                user_data.client.ws = null;
              }
            },
            sendPingsAutomatically: true,
            upgrade: (res, req, context) => {
              const env = prepare_env(req, self);
              env.set('rack.upgrade?', #{:websocket});
              const rack_res = #@app.$call(env);
              const handler = env.get('rack.upgrade');
              if (rack_res[0] < 300 && handler && handler !== nil) {
                const client = ouwc.$new();
                client.env = env;
                client.open = false;
                client.handler = handler
                client.protocol = #{:websocket};
                client.server = self;
                client.timeout = 120;
                if (#@worker) {
                  client.worker = true;
                }
                res.upgrade({ client: client },
                  req.getHeader('sec-websocket-key'),
                  req.getHeader('sec-websocket-protocol'),
                  req.getHeader('sec-websocket-extensions'),
                  context);
              } else {
                if (rack_res[0] >= 300) {
                  env.delete('rack.upgrade');
                }
                res.writeStatus(rack_res[0].toString() + ' OK');
                handle_headers(rack_res[1], res);
                handle_response(rack_res[2], res);
                res.end();
              }
            },

          });
          #@server.listen(#@port, #@host, () => { console.log(`Server is running on ${#@scheme}://${#@host}:${#@port}`)});
        }
      end

      def publish(channel, message)
        %x{
          if (typeof channel === "object") {
            channel = channel.toString();
          }
          if (!message.$$is_string) {
            message = JSON.stringify(message);
          }
          if (typeof message === "object") {
            message = message.toString();
          }
          #@server.publish(channel, message);
        }
      end

      def stop
        if Up::CLI::stoppable?
          `#@server.close()`
          @server = nil
          ::Up.instance_variable_set(:@instance, nil)
        end
      end
    end
  end
end
