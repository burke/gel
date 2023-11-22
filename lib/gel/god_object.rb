# frozen_string_literal: true

require_relative "load_path_manager"

class Gel::GodObject
  IGNORE_LIST = %w(bundler gel rubygems-update)

  class Impl
    def __set_gemfile(o)
      @gemfile = o
    end
    def __gemfile = @gemfile
    def __store = @store

    def initialize
      @config = nil
      @gemfile = nil
      @active_lockfile = false
    end

    def config
      @config ||= Gel::Config.new
    end

    def resolve_gem_path(path)
      Stateless.resolve_gem_path(@store, Gel::LoadPathManager.activated_gems, path, &method(:activate_gems_now))
    end

    def gem(name, *requirements, why: nil)
      Stateless.gem(@store, Gel::LoadPathManager.activated_gems, name, *requirements, why: why, &method(:activate_gems_now))
    end

    def open(store)
      @store = store
      Stateless.activate_locked_gems(@store, &method(:activate_gems_now))
    end

    def load_gemfile(path = nil, error: true)
      @gemfile ||= Stateless.load_gemfile(@gemfile, path, error: error)
    end

    def activate(fast: false, install: false, output: nil, error: true)
      @active_lockfile ||= Stateless.activate(@active_lockfile, load_gemfile(error: error), @store, @gemfile, fast: fast, output: output) do |loader|
        require_relative "../../slib/bundler"
        locked_store = loader.activate(Gel.environment, @store.root_store, install: install, output: output)
        open(locked_store)
      end
      nil
    end

    def install_gem(catalogs, gem_name, requirements = nil, output: nil, solve: true)
      Stateless.install_gem(@store, catalogs, gem_name, requirements, output: output, solve: solve) do |loader|
        locked_store = loader.activate(Gel.environment, @store.root_store, install: true, output: output)
        open(locked_store)
      end
    end

    def activate_gems_now(preparation, activation, lib_dirs)
      @store.prepare(preparation)
      Gel::LoadPathManager.activate(activation, lib_dirs)
    end

    def activate_for_executable(exes, install: false, output: nil)
      loaded_gemfile = load_gemfile(error: false)
      Stateless.activate_for_executable(loaded_gemfile, @store, Gel::LoadPathManager.activated_gems, @gemfile, exes, install: install, output: output, activate_gems_now: method(:activate_gems_now)) do |loader|
        locked_store = loader.activate(Gel.environment, @store.root_store, install: install, output: output)

        ret = nil
        exes.each do |exe|
          if locked_store.each.any? { |g| g.executables.include?(exe) }
            open(locked_store)
            ret = :lock
            break
          end
        end
        ret
      end
    end
  end
end

require_relative "god_object/stateless"
