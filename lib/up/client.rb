# backtick_javascript: true
if RUBY_ENGINE == 'opal'
  %x{
    const process = require('node:process');
  }
end

module Up
  class Client
    # instance vars are set by the server

    attr_reader :env, :handler, :protocol, :timeout

    def handler=(h)
      @handler.on_close(self)
      @handler = h
      @handler.on_open(self)
    end

    def open?
      @open
    end

    def pubsub?
      true
    end

    if RUBY_ENGINE == 'opal'
      def close
        @open = false
        `#@ws?.close()`
      end

      def pending
        return -1 unless @open
        `#@ws?.getBufferedAmount()`
      end

      def publish(channel, message)
        res = false
        %x{
          if (!message.$$is_string) {
            message = JSON.stringify(message);
          }
          res = #@server?.publish(channel, message);
          if (self.worker) {
            process.send({c: channel, m: message});
          }
        }
        res
      end

      def subscribe(channel, is_pattern = false, &block)
        @sub_block = block
        `#@ws?.subscribe(channel)`
      end

      def unsubscribe(channel, is_pattern = false)
        `#@ws?.unsubscribe(channel)`
      end

      def write(data)
        `#@ws?.send(data, false)`
      end
    end
  end
end
