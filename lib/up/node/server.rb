# backtick_javascript: true
require 'logger'
require 'stringio'
require 'up/cli'
require 'up/pub_sub_client'

%x{
  const process = require('node:process');
  module.paths.push(process.cwd() + '/node_modules');
  const http = require('node:http');
  const https = require('node:https');
  const http2 = require('node:http2');
  const fs = require('node:fs');
  const web_socket = require('ws');
  const channels = new Map();
}

module Up
  class << self
    def publish(channel, message)
      raise 'no instance running' unless @instance
      @instance.publish(channel, message)
    end
  end

  module Node
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
        raise "unsupported scheme #{@scheme}" unless %w[http http2 https].include?(@scheme)
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
          raise "for https or http2 :key_file and :cert_file args must be given"
        end
        @pid_file  = pid_file
        @server    = nil
        @logger    = logger
        @t_factory = proc { |filename, _content_type| File.new(filename, 'a+') }
      end

      %x{
        function ws_subscribe(channel, ws) {
          let c = channels.get(channel);
          if (!c) {
            c = new Set();
            channels.set(channel, c);
          }
          c.add(ws);
        }

        function ws_unsubscribe(channel, ws) {
          let c = channels.get(channel);
          if (c) {
            c.delete(ws);
          }
        }

        function handle_headers(rack_headers, srv_res) {
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

        function handle_response(parts, srv_res) {
          if (parts.$$is_array) {
            let i = 0, l = parts.length, part;
            for (; i < l; i++) {
              part = parts[i];
              srv_res.write(typeof part === "object" && part.$$is_string ? part.toString() : part);
            }
          } else {
            if (parts.$each && parts["$respond_to?"]('each')) {
              #{`parts`.each { |part|
                `srv_res.write(typeof part === "object" && part.$$is_string ? part.toString() : part)`
              }}
            } else if (parts.$call && parts["$respond_to?"]('call')) {
              let part = parts.$call();
              srv_res.write(typeof part === "object" && part.$$is_string ? part.toString() : part);
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
            .set('SERVER_PROTOCOL', 'HTTP/' + req.httpVersion)
            .set('SERVER_NAME', ins.host)
            .set('SERVER_PORT', ins.port_s)
            .set('REQUEST_METHOD', req.method);
          let qi = req.url.indexOf('?');
          if (qi > 0) {
            env.set('QUERY_STRING', req.url.slice(qi + 1)).set('PATH_INFO', req.url.slice(0, qi));
          } else {
            env.set('QUERY_STRING', '').set('PATH_INFO', req.url);
          }
          let hdr, hdru, hds = req.headers;
          for (hdr in hds) {
            hdru = hdr.toUpperCase().replaceAll('-', '_');
            if (hdru[0] === 'C' && (hdru === 'CONTENT_TYPE' || hdru === 'CONTENT_LENGTH')) {
              env.set(hdru, hds[hdr]);
            } else {
              env.set('HTTP_' + hdru, hds[hdr]);
            }
          }
          return env;
        }
      }

      def listen
        raise "already running" if @server
        ::Up.instance_variable_set(:@instance, self)
        ::File.write(@pid_file, `process.pid.toString()`) if @pid_file
        # TODO use logger
        puts "Server PID: #{`process.pid`}"
        %x{
          const ouns = Opal.Up.Node.Server;
          const ouwc = Opal.Up.PubSubClient;
          const deco = new TextDecoder();
          function handler(req, res) {
            const rack_res = #@app.$call(prepare_env(req, self));
            res.statusCode = rack_res[0];
            handle_headers(rack_res[1], res);
            handle_response(rack_res[2], res);
            res.end();
          }
          let options = {};
          if (#@scheme == 'https' || #@scheme == 'http2') {
            options.cert = fs.readFileSync(#@cert_file);
            options.key = fs.readFileSync(#@key_file);
            if (#@ca_file && #@ca_file != nil) { options.ca = fs.readFileSync(#@ca_file); }
          }
          if (#@scheme == 'https') {
            #@server = https.createServer(options, handler);
          } else if (#@scheme == 'http2') {
            options.allowHTTP1 = true;
            #@server = http2.createSecureServer(options, handler);
          } else if (#@scheme == 'http') {
            #@server = http.createServer(handler);
          }
          #@ws_server = new web_socket.WebSocketServer({ noServer: true });
          #@server.on('upgrade', function (req, socket, head) {
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
              #@ws_server.handleUpgrade(req, socket, head, function (ws, req) {
                ws.on('close', (code, message) => {
                  if (typeof(client.handler.$on_close) === 'function') {
                    client.ws = ws;
                    client.open = false;
                    client.handler.$on_close(client);
                    client.ws = null;
                  }});
                ws.on('message', (message, isBinary) => {
                  if (typeof(client.handler.$on_message) === 'function') {
                    const msg = deco.decode(message);
                    client.ws = ws;
                    client.handler.$on_message(client, msg);
                    client.ws = null;
                }});
                ws.subscribe = (channel) => { ws_subscribe(channel, ws); }
                ws.unsubscribe = (channel) => { ws_unsubscribe(channel, ws); }
                if (typeof(client.handler.$on_open) === 'function') {
                  if (ws.readyState === 1) {
                    client.ws = ws;
                    client.open = true;
                    client.handler.$on_open(client);
                    client.ws = null;
                  } else {
                    ws.on('open', function() {
                      client.ws = ws;
                      client.open = true;
                      client.handler.$on_open(client);
                      client.ws = null;
                    });
                  }
                }
              });
            } else {
              if (rack_res[0] >= 300) {
                env.delete('rack.upgrade');
              }
              res.statusCode = rack_res[0];
              handle_headers(rack_res[1], res);
              handle_response(rack_res[2], res);
              res.end();
            }
          });
          #@server.listen(#@port, #@host, ()=>{ console.log(`Server is running on ${#@scheme}://${#@host}:${#@port}`)});
        }
      end

      def publish(channel, message)
        internal_publish(channel, message)
      end

      def internal_publish(channel, message)
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
          let client, clients = channels.get(channel);
          if (clients) {
            for(client of clients) {
              if (client.readyState === 1) {
                // open
                client.send(message);
              } else if (client.readyState > 1) {
                // closing or closed
                clients.delete(client);
              }
            }
            if (clients.size == 0) {
              channels.delete(channel);
            }
          }
        }
      end

      def stop
        if Up::CLI::stoppable?
          `#@server.close()`
          `#@ws_server.close()`
          @server = nil
          @ws_server = nil
          ::Up.instance_variable_set(:@instance, nil)
        end
      end
    end
  end
end
