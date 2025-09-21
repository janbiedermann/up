# backtick_javascript: true
module Up
  module CLI
    def self.eval_js(js)
      # this may return a Promise
      `eval(js.toString())`
    end
  end
end
