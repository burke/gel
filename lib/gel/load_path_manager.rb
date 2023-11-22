module Gel::LoadPathManager
  @activated_gems = {}
  class << self
    attr_reader :activated_gems
  end

  def self.activate(activation, lib_dirs)
    @activated_gems.update(activation)
    $LOAD_PATH.concat lib_dirs
  end
end
