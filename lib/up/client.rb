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
        %x{
          if (#@ws) {
            if (typeof #@ws.getBufferedAmount === "function") {
              // uWS
              return #@ws.getBufferedAmount();
            } else {
              // node ws
              return #@ws.bufferedAmount;
            }
          }
        }
      end

      def publish(channel, message)
        res = false
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
          res = #@server?.$publish(channel, message);
        }
        res
      end

      def subscribe(channel, is_pattern = false, &block)
        @sub_block = block
        %x{
          if (typeof channel === "object") {
            channel = channel.toString();
          }
          #@ws?.subscribe(channel)
        }
      end

      def unsubscribe(channel, is_pattern = false)
        %x{
          if (typeof channel === "object") {
            channel = channel.toString();
          }
          #@ws?.unsubscribe(channel)
        }
      end

      def write(data)
        %x{
          if (data.$$is_string && typeof data === "object") {
            data = data.toString();
          }
          #@ws?.send(data, false)
        }
      end
    end
  end
end
