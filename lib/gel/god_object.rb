# frozen_string_literal: true

require_relative "load_path_manager"

class Gel::GodObject
  IGNORE_LIST = %w(bundler gel rubygems-update)

  class Impl
    def __store = @store

    def initialize(store)
      @store = store
      @active_lockfile = false
      Stateless.activate_locked_gems(@store, &method(:activate_gems_now))
    end

    def activate_gems_now(preparation, activation, lib_dirs)
      @store.prepare(preparation)
      Gel::LoadPathManager.activate(activation, lib_dirs)
    end
  end
end

require_relative "god_object/stateless"
