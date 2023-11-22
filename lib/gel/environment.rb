# frozen_string_literal: true

require_relative "god_object"

class Gel::Environment
  def initialize(store)
    @store = store
    Gel::GodObject::Stateless.activate_locked_gems(store, &method(:activate_gems_now))
  end

  # Just accessors for global state bits
  attr_reader :gemfile
  def store = @store

  # only used in tests
  attr_writer :gemfile

  # Read-only
  def lockfile_name(gemfile = @gemfile&.filename) = Gel::GodObject::Stateless.lockfile_name(gemfile)
  def filtered_gems(gems = @gemfile.gems) = Gel::GodObject::Stateless.filtered_gems(gems)
  def find_executable(exe, gem_name = nil, gem_version = nil) = Gel::GodObject::Stateless.find_executable(@store, exe, gem_name, gem_version)
  def find_gem(name, *requirements, &condition) = Gel::GodObject::Stateless.find_gem(@store, name, *requirements, &condition)
  def find_gemfile(path = nil, error: true) = Gel::GodObject::Stateless.find_gemfile(@gemfile, path, error: error)
  def gem_for_path(path) = Gel::GodObject::Stateless.gem_for_path(@store, Gel::LoadPathManager.activated_gems, path)
  def locked? = Gel::GodObject::Stateless.locked?(@store)
  def write_lock(output: nil, lockfile: lockfile_name, **args) = Gel::GodObject::Stateless.write_lock(load_gemfile, @store, output: output, lockfile: lockfile, **args)
  # gem_has_file? and scoped_require exclusively used by GemfileParser#autorequire
  def gem_has_file?(gem_name, path) = Gel::GodObject::Stateless.gem_has_file?(@store, Gel::LoadPathManager.activated_gems, gem_name, path)
  # requires are obviously side effects.. how can we flag these clearly?
  def scoped_require(gem_name, path) = Gel::GodObject::Stateless.scoped_require(@store, Gel::LoadPathManager.activated_gems, gem_name, path)
  def require_groups(*groups) = Gel::GodObject::Stateless.require_groups(@gemfile, *groups)

  # Significant mutations below

  def gem(name, *requirements, why: nil)
    Gel::GodObject::Stateless.gem(@store, Gel::LoadPathManager.activated_gems, name, *requirements, why: why, &method(:activate_gems_now))
  end

  def activate(fast: false, install: false, output: nil, error: true)
    @active_lockfile ||= Gel::GodObject::Stateless.activate(@active_lockfile, load_gemfile(error: error), @store, @gemfile, fast: fast, output: output) do |loader|
      require_relative "../../slib/bundler"
      locked_store = loader.activate(Gel.environment, @store.root_store, install: install, output: output)
      Gel::GodObject::Stateless.activate_locked_gems(locked_store, &method(:activate_gems_now))
    end
    nil
  end

  def install_gem(catalogs, gem_name, requirements = nil, output: nil, solve: true)
    Gel::GodObject::Stateless.install_gem(@store, catalogs, gem_name, requirements, output: output, solve: solve) do |loader|
      locked_store = loader.activate(Gel.environment, @store.root_store, install: true, output: output)
      Gel::GodObject::Stateless.activate_locked_gems(locked_store, &method(:activate_gems_now))
    end
  end

  def resolve_gem_path(path)
    Gel::GodObject::Stateless.resolve_gem_path(@store, Gel::LoadPathManager.activated_gems, path, &method(:activate_gems_now))
  end

  def activate_for_executable(exes, install: false, output: nil)
    loaded_gemfile = load_gemfile(error: false)
    Gel::GodObject::Stateless.activate_for_executable(loaded_gemfile, @store, Gel::LoadPathManager.activated_gems, @gemfile, exes, install: install, output: output, activate_gems_now: method(:activate_gems_now)) do |loader|
      locked_store = loader.activate(Gel.environment, @store.root_store, install: install, output: output)

      ret = nil
      exes.each do |exe|
        if locked_store.each.any? { |g| g.executables.include?(exe) }
          Gel::GodObject::Stateless.activate_locked_gems(locked_store, &method(:activate_gems_now))
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

  def load_gemfile(path = nil, error: true)
    @gemfile ||= Gel::GodObject::Stateless.load_gemfile(@gemfile, path, error: error)
  end
end
