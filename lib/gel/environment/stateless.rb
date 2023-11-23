# frozen_string_literal: true

require "rbconfig"

require_relative "../util"
require_relative "../host_system"
require_relative "../stdlib"
require_relative "../path_resolver"
require_relative "../gem_set_solver"

# This module contains a bunch of behaviour for Gel.environment.
# Some of it is pretty thorny and could use a reafactor, but what is here
# notably doesn't mutate any state on the Gel.environment except through callbacks.
#
# This is a transitional state: Environment needs to be split up a bit and this is
# a temporary home for this code while I pick it apart a bit more.
module Gel::Environment::Stateless
  class << self
    def locked?(store) = store.is_a?(Gel::LockedStore)

    def find_executable(store, exe, gem_name = nil, gem_version = nil)
      store.each(gem_name) do |g|
        next if gem_version && g.version != gem_version
        return File.join(g.root, g.bindir, exe) if g.executables.include?(exe)
      end
      nil
    end

    def filtered_gems(gems)
      platforms = Gel::HostSystem::GEMFILE_PLATFORMS.map(&:to_s)
      gems.reject do |_, _, options|
        platform_options = Array(options[:platforms]).map(&:to_s)

        next true if platform_options.any? && (platform_options & platforms).empty?
        next true unless options.fetch(:install_if, true)
      end
    end

    def find_gemfile(current_gemfile, path = nil, error: true)
      if path && current_gemfile && current_gemfile.filename != File.expand_path(path)
        raise Gel::Error::CannotActivateError.new(path: path, gemfile: current_gemfile.filename)
      end
      return current_gemfile.filename if current_gemfile

      path ||= ENV["GEL_GEMFILE"]
      path ||= Gel::Util.search_upwards("Gemfile")
      path ||= "Gemfile"

      if File.exist?(path)
        path
      elsif error
        raise Gel::Error::NoGemfile.new(path: path)
      end
    end

    def lockfile_name(gemfile)
      ENV["GEL_LOCKFILE"] || (gemfile && gemfile + ".lock") || "Gemfile.lock"
    end

    def activate(active_lockfile, loaded_gemfile, store, active_gemfile, fast: false, output: nil)
      return(active_lockfile) if loaded_gemfile.nil?
      return(active_lockfile) if active_lockfile

      lockfile = lockfile_name(loaded_gemfile.filename)
      if File.exist?(lockfile)
        resolved_gem_set = Gel::ResolvedGemSet.load(lockfile, git_depot: store.git_depot)
        resolved_gem_set = nil if !fast && lock_outdated?(loaded_gemfile, resolved_gem_set)
      end

      return(active_lockfile) if fast && !resolved_gem_set

      resolved_gem_set ||= write_lock(loaded_gemfile, store, output: output, lockfile: lockfile)

      loader = Gel::LockLoader.new(resolved_gem_set, active_gemfile)
      yield(loader)

      true # there is now an active lockfile
    end

    def gem(store, activated_gems, name, *requirements, why: nil, &block)
      return if Gel::Environment::IGNORE_LIST.include?(name)

      requirements = Gel::Support::GemRequirement.new(requirements)

      if existing = activated_gems[name]
        if existing.satisfies?(requirements)
          return
        else
          raise Gel::Error::AlreadyActivatedError.new(
            name: name,
            existing: existing.version,
            requirements: requirements,
            why: why,
          )
        end
      end

      found_any = false
      gem = store.each(name).find do |g|
        found_any = true
        g.satisfies?(requirements)
      end

      if gem
        activate_gem(store, activated_gems, gem, why: why, &block)
      else
        raise Gel::Error::UnsatisfiedDependencyError.new(
          name: name,
          was_locked: locked?(store),
          found_any: found_any,
          requirements: requirements,
          why: why,
        )
      end
    end

    def resolve_gem_path(store, activated_gems, path, &block)
      path = path.to_s # might be e.g. a Pathname

      gem, file, resolved = Gel::PathResolver.resolve(store, activated_gems, path)

      if file
        if gem && resolved
          activate_gems(resolved, &block)
        else
          unless resolved
            # This is a cheat: we're assuming the caller is about to require
            # the file
            Gel::Stdlib.instance.activate(path)
          end
        end

        return file
      elsif resolved
        raise resolved
      end

      path
    end

    def scoped_require(store, activated_gems, gem_name, path)
      if full_path = gem_has_file?(store, activated_gems, gem_name, path)
        yield full_path
      else
        raise ::LoadError, "No file #{path.inspect} found in gem #{gem_name.inspect}"
      end
    end

    def find_gem(store, name, *requirements, &condition)
      requirements = Gel::Support::GemRequirement.new(requirements)

      store.each(name).find do |g|
        g.satisfies?(requirements) && (!condition || condition.call(g))
      end
    end

    # NOTE: untested
    def require_groups(gemfile, *groups)
      gems = filtered_gems(gemfile.gems)
      groups = [:default] if groups.empty?
      groups = groups.map(&:to_s)
      gems = gems.reject { |g| ((g[2][:group] || [:default]).map(&:to_s) & groups).empty? }
      yield gems
    end

    def write_lock(gemfile, store, output: nil, lockfile: lockfile_name, **args)
      gem_set = Gel::GemSetSolver.solve_for_gemfile(
        store: store, output: output, gemfile: gemfile, lockfile: lockfile,
        **args
      )

      if lockfile
        output.puts "Writing lockfile to #{File.expand_path(lockfile)}" if output
        File.write(lockfile, gem_set.dump)
      end

      gem_set
    end

    def install_gem(store, catalogs, gem_name, requirements = nil, output: nil, solve: true)
      gemfile = Gel::GemfileParser.inline do
        source "https://rubygems.org"
        gem gem_name, *requirements
      end

      gem_set = Gel::GemSetSolver.solve_for_gemfile(
        store: store, output: output, solve: solve, gemfile: gemfile, lockfile: lockfile_name(gemfile),
      )

      loader = Gel::LockLoader.new(gem_set)
      yield(loader)
    end

    def load_gemfile(gemfile, path = nil, error: true)
      path = find_gemfile(@gemfile, path, error: error)
      return if path.nil?

      content = File.read(path)
      Gel::GemfileParser.parse(content, path, 1)
    end

    def activate_locked_gems(store, &block)
      if store.respond_to?(:locked_versions) && store.locked_versions
        gems = store.gems(store.locked_versions)
        activate_gems(gems.values, &block)
      end
    end

    def activate_for_executable(loaded_gemfile, store, activated_gems, active_gemfile, exes, activate_gems_now:, install: false, output: nil, &block)
      resolved_gem_set = nil
      outdated_gem_set = nil
      load_error = nil

      if loaded_gemfile
        lockfile = lockfile_name(loaded_gemfile.filename)
        if File.exist?(lockfile)
          resolved_gem_set = Gel::ResolvedGemSet.load(lockfile, git_depot: store.git_depot)

          if lock_outdated?(loaded_gemfile, resolved_gem_set)
            outdated_gem_set = resolved_gem_set
            resolved_gem_set = nil
          end
        end

        if resolved_gem_set
          loader = Gel::LockLoader.new(resolved_gem_set, active_gemfile)

          begin
            res = yield(loader)
            return res if res
          rescue Gel::Error::MissingGemError => ex
            load_error = ex
          end
        end
      end

      locked_gems =
        if resolved_gem_set
          resolved_gem_set.gem_names
        elsif loaded_gemfile
          loaded_gemfile.gem_names | (outdated_gem_set&.gem_names || [])
        else
          []
        end

      active_gemfile = nil
      exes.each do |exe|
        candidates = store.each.select { |g| g.executables.include?(exe) }

        locked_candidates, unlocked_candidates =
          candidates.partition { |g| locked_gems.include?(g.name) }

        # If we failed to load the lockfile, but we've now found a candidate
        # supplied by a locked gem, it's time to fail: we have to run locked
        # gems in a locked environment, and we can't do that right now.
        # The user probably needs to run `gel install`, which is what this
        # error will tell them to do.
        if locked_candidates.any?
          if load_error
            raise load_error
          elsif outdated_gem_set
            raise Gel::Error::OutdatedLockfileError
          elsif resolved_gem_set.nil?
            raise Gel::Error::NoLockfileError
          else
            # The lockfile was up-to-date and fully processed; we can
            # continue and ignore the locked candidates. This could happen
            # if non-locked versions of locked gems supply the executable.
            # We could still succeed if an unlocked_candidate can fill in.
          end
        end

        # Specific situation, but plausible enough to warrant a more
        # helpful error: there's no ambiguity about who owns the
        # executable name, but the one gem that supplies it is locked to a
        # version that doesn't have it.
        if unlocked_candidates.empty? && locked_candidates.map(&:name).uniq.size == 1
          # We're going to describe the set of versions (that we know
          # about) that would have supplied the executable.
          valid_versions = locked_candidates.map(&:version).uniq.map { |v| Gel::Support::Version.new(v) }.sort
          locked_version = Gel::Support::Version.new(resolved_gem_set.gems[locked_candidates.first.name].version)

          # Most likely, our not-executable-having version is outside some
          # contiguous range of executable-having versions, so let's check
          # for that, because it'll give us a shorter error message.
          #
          # (Note we assume but don't prove that every version we know
          # about within the range does have the executable. If that
          # assumption is wrong, the user will get the full list after
          # they retry with a bad in-range version.)
          if valid_versions.first > locked_version || valid_versions.last < locked_version
            valid_versions = valid_versions.first.to_s..valid_versions.last.to_s
          elsif valid_versions.size == 1
            valid_versions = valid_versions.first.to_s
          else
            valid_versions = valid_versions.map(&:to_s)
          end

          raise Gel::Error::MissingExecutableError.new(
            executable: exe,
            gem_name: locked_candidates.first.name,
            gem_versions: valid_versions,
            locked_gem_version: locked_version.to_s,
          )
        end

        case candidates.size
        when 0
          nil
        when 1
          # NOTE: untested
          gem(store, activated_gems, candidates.first.name, &activate_gems_now)
          return :gem
        else
          # Multiple gems can supply this executable; do we have any
          # useful way of deciding which one should win? One obvious
          # tie-breaker: if a gem's name matches the executable, it wins.

          # NOTE: untested
          if candidates.map(&:name).include?(exe)
            gem(store, activated_gems, exe, &activate_gems_now)
          else
            gem(store, activated_gems, candidates.first.name, &activate_gems_now)
          end

          return :gem
        end
      end

      nil
    end

    def gem_has_file?(store, activated_gems, gem_name, path)
      search_name, search_ext = Gel::Util.split_filename_for_require(path)

      store.gems_for_lib(search_name) do |gem, subdir, ext|
        next unless Gel::Util.ext_matches_requested?(ext, search_ext)

        if gem.name == gem_name && gem == activated_gems[gem_name]
          return gem.path(path, subdir)
        end
      end

      false
    end

    private

    def activate_gem(store, activated_gems, gem, why: nil, &block)
      raise gem.version.class.name unless gem.version.class == String
      if activated_gems[gem.name]
        raise activated_gems[gem.name].version.class.name unless activated_gems[gem.name].version.class == String
        return if activated_gems[gem.name].version == gem.version

        raise Gel::Error::AlreadyActivatedError.new(
          name: gem.name,
          existing: activated_gems[gem.name].version,
          requested: gem.version,
          why: why,
        )
      end

      gem.dependencies.each do |dep, reqs|
        gem(store, activated_gems, dep, *reqs.map { |(qual, ver)| "#{qual} #{ver}" }, why: ["required by #{gem.name} #{gem.version}", *why], &block)
      end

      activate_gems([gem], &block)
    end

    def lock_outdated?(gemfile, resolved_gem_set)
      gemfile_dependencies(gemfile: gemfile) != resolved_gem_set.dependencies
    end

    # TODO: duplicate method
    def gemfile_dependencies(gemfile:)
      gemfile.gems.
        group_by { |name, _constraints, _options| name }.
        map do |name, list|

        constraints = list.flat_map { |_, c, _| c }.compact

        if constraints == []
          name
        else
          r = Gel::Support::GemRequirement.new(constraints)
          req_strings = r.requirements.sort_by { |(_op, ver)| [ver, ver.segments] }.map { |(op, ver)| "#{op} #{ver}" }

          "#{name} (#{req_strings.join(", ")})"
        end
      end.sort
    end

    def activate_gems(gems)
      lib_dirs = gems.flat_map(&:require_paths)
      preparation = {}
      activation = {}

      gems.each do |g|
        preparation[g.name] = g.version
        activation[g.name] = g
      end

      yield(preparation, activation, lib_dirs)
    end
  end
end
