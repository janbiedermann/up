class RackApp
  def self.call(env)
    [200, {}, [env.to_s]]
  end
end
