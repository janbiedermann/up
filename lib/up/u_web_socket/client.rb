# backtick_javascript: true

module Up
  module UWebSocket
    class Client
      # instance vars are set by the server

      attr_reader :handler, :protocol, :timeout

      def close
        @open = false
        `#@ws.close()`
      end

      def env
        @env
      end

      def handler=(h)
        @handler.on_close(self)
        @handler = h
        @handler.on_open(self)
      end

      def open?
        @open
      end

      def pending
        `#@ws.getBufferedAmount()`
      end

      def pubsub?
        false
      end

      def write(data)
        `#@ws.send(data, false)`
      end
    end
  end
end
