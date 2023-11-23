# frozen_string_literal: true

require_relative "load_path_manager"

class Gel::Environment
end

require_relative "environment/stateless"
require_relative "environment/activation"

class Gel::Environment
  IGNORE_LIST = %w(bundler gel rubygems-update)

  def initialize(store)
    @store = store
    Activation.activate_locked_gems(store, &method(:activate_gems_now))
  end

  # Just accessors for global state bits
  attr_reader :gemfile
  attr_reader :store

  # only used in tests
  attr_writer :gemfile

  # Read-only
  def lockfile_name(gemfile = @gemfile&.filename) = Activation.lockfile_name(gemfile)
  def filtered_gems(gems = @gemfile.gems) = Stateless.filtered_gems(gems)
  def find_executable(exe, gem_name = nil, gem_version = nil) = Stateless.find_executable(@store, exe, gem_name, gem_version)
  def find_gem(name, *requirements, &condition) = Stateless.find_gem(@store, name, *requirements, &condition)
  def find_gemfile(path = nil, error: true) = Stateless.find_gemfile(@gemfile, path, error: error)
  def locked? = @store&.locked?
  def write_lock(output: nil, lockfile: lockfile_name, **args) = Activation.write_lock(load_gemfile, @store, output: output, lockfile: lockfile, **args)
  # gem_has_file? and scoped_require exclusively used by GemfileParser#autorequire
  def gem_has_file?(gem_name, path) = Stateless.gem_has_file?(@store, Gel::LoadPathManager.activated_gems, gem_name, path)

  def gem_for_path(path) = Gel::PathResolver.resolve(@store, Gel::LoadPathManager.activated_gems, path)

  # Significant mutations below

  def scoped_require(gem_name, path)
    Stateless.scoped_require(@store, Gel::LoadPathManager.activated_gems, gem_name, path) do |full_path|
      require full_path
    end
  end

  def require_groups(*groups)
    Stateless.require_groups(@gemfile, *groups) do |gems|
      @gemfile.autorequire(self, gems)
    end
  end

  def gem(name, *requirements, why: nil)
    Activation.gem(@store, Gel::LoadPathManager.activated_gems, name, *requirements, why: why, &method(:activate_gems_now))
  end

  def activate(fast: false, install: false, output: nil, error: true)
    @active_lockfile ||= Activation.activate(@active_lockfile, load_gemfile(error: error), @store, @gemfile, fast: fast, output: output) do |loader|
      require_relative "../../slib/bundler"
      locked_store = loader.activate(self, @store.root_store, install: install, output: output)
      reopen(locked_store)
      @store = locked_store # FIX?
      Activation.activate_locked_gems(locked_store, &method(:activate_gems_now))
    end
    nil
  end

  def install_gem(catalogs, gem_name, requirements = nil, output: nil, solve: true)
    Activation.install_gem(@store, catalogs, gem_name, requirements, output: output, solve: solve) do |loader|
      locked_store = loader.activate(self, @store.root_store, install: true, output: output)
      reopen(locked_store)
    end
  end

  def resolve_gem_path(path)
    Activation.resolve_gem_path(@store, Gel::LoadPathManager.activated_gems, path, &method(:activate_gems_now))
  end

  def activate_for_executable(exes, install: false, output: nil)
    loaded_gemfile = load_gemfile(error: false)
    Activation.activate_for_executable(loaded_gemfile, @store, Gel::LoadPathManager.activated_gems, @gemfile, exes, install: install, output: output, activate_gems_now: method(:activate_gems_now)) do |loader|
      locked_store = loader.activate(self, @store.root_store, install: install, output: output)

      ret = nil
      exes.each do |exe|
        if locked_store.each.any? { |g| g.executables.include?(exe) }
          reopen(locked_store)
          ret = :lock
          break
        end
      end
      ret
    end
  end

  def activate_gems_now(preparation, activation, lib_dirs)
    @store.prepare(preparation)
    Gel::LoadPathManager.activate(activation, lib_dirs)
  end

  private

  def reopen(store)
    @store = store
    Activation.activate_locked_gems(store, &method(:activate_gems_now))
  end

  def load_gemfile(path = nil, error: true)
    @gemfile ||= Stateless.load_gemfile(@gemfile, path, error: error)
  end
end
