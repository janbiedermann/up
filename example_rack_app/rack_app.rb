class RackApp
  def self.call(env)
    # [200, {}, [env.to_s]]
    [200, {}, ["hello world"]]
  end
end
