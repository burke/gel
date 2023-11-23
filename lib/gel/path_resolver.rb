module Gel::PathResolver
  class << self
    def gem_for_path(store, activated_gems, path)
      gem, _file, _resolved = resolve(store, activated_gems, path)
      gem
    end

    # Search gems and stdlib for how we should load the given +path+
    #
    # Returns nil when the path is unrecognised (caller should fall back to
    # scanning $LOAD_PATH). Otherwise, returns an array tuple:
    #
    # [
    #   gem,        # nil == stdlib
    #   file,       # full path to require, or nil if gem is conflicted
    #   resolved,   # if gem: array of gems to activate, or nil if empty
    #               # if conflicted: string describing conflict
    #               # if stdlib: boolean whether the file is known to already
    #               # be loaded (may return false negative)
    # ]
    def resolve(store, activated_gems, path)
      if store && !path.start_with?("/")
        search_name, search_ext = Gel::Util.split_filename_for_require(path)

        # Fast scan first: find all the gems that supply a file matching
        # +search_name+ (ignoring ext for now)
        hits = []
        store.gems_for_lib(search_name) do |gem, subdir, ext|
          hits << [gem, subdir, ext]
        end

        # Now we get a bit more detailed: 1) skip any results that don't
        # match the +search_ext+; 2) immediately return if we've matched a
        # gem that's already loaded.
        results = []
        hits.each do |gem, subdir, ext|
          next unless Gel::Util.ext_matches_requested?(ext, search_ext)

          if activated_gems[gem.name] == gem
            return [gem, gem.path(path, subdir), nil]
          else
            results << [gem, subdir, ext]
          end
        end

        # Okay, no already-loaded gems supply the file we're looking for.
        # +results+ contains a list of gems that we could load.

        # Before we start gaming out dependency trees for gems we could load,
        # it's time to check whether we've already loaded this file from
        # stdlib.
        stdlib = Gel::Stdlib.instance

        stdlib_path = stdlib.resolve(search_name, search_ext)
        stdlib_path += search_ext if stdlib_path && search_ext

        if stdlib_path && stdlib.active?(path)
          # Yep, we don't need to do anything
          return [nil, stdlib_path, true]
        end

        # We're going to have to activate a gem if we can. Recursively plan
        # out the set of dependencies we need to activate... or alternatively,
        # identify the conflict that prevents it.
        first_activation_error = nil
        results.each do |gem, subdir, ext|
          a = gems_for_activation(store, activated_gems, gem, why: ["provides #{path.inspect}"])
          if a.is_a?(Array)
            # This is a valid dependency set; activate +a+, and require the
            # file.
            return [gem, gem.path(path, subdir), a]
          else
            # If we don't find a better answer later in this loop (or in
            # +stdlib_path+), then this will be the failure we report.
            first_activation_error ||= [gem, nil, a]
          end
        end

        # We didn't find any viable gems to activate, so now we consider
        # whether we previously found a not-yet-loaded stdlib file.
        if stdlib_path
          return [nil, stdlib_path, false]
        end

        # Still no luck: this file cannot be resolved. If we found a gem that
        # was blocked by a conflict, we'll return the explanation as a string.
        # Otherwise (no installed gems have any knowledge of this file) we
        # return nil.
        first_activation_error
      end
    end

    private

    # Returns either an array of compatible gems that must all be activated
    # (in the specified order) to activate the given +gem+, or a LoadError
    # describing a dependency conflict that prevents it.
    #
    ##
    #
    # Recurses using internal +context+ as a hash of additional gems to
    # consider already activated. This is used to identify internal conflicts
    # between pending dependencies.
    def gems_for_activation(store, activated_gems, gem, why: nil, context: {})
      if active_gem = activated_gems[gem.name] || context[gem.name]
        # This gem name is already active. Either it's the right version, and
        # we have nothing to do, or it's the wrong version, and we're unable
        # to proceed.
        if active_gem == gem
          return []
        else
          return Gel::Error::AlreadyActivatedError.new(
            name: gem.name,
            existing: active_gem.version,
            requested: gem.version,
            why: why,
          )
        end
      end

      context = context.dup
      new_gems = [gem]
      context[gem.name] = gem

      gem.dependencies.each do |dep, reqs|
        next if Gel::Environment::IGNORE_LIST.include?(dep)

        inner_why = ["required by #{gem.name} #{gem.version}", *why]

        requirements = Gel::Support::GemRequirement.new(
          reqs.map { |(qual, ver)| "#{qual} #{ver}" }
        )

        if existing = activated_gems[dep] || context[dep]
          if existing.satisfies?(requirements)
            next
          else
            return Gel::Error::AlreadyActivatedError.new(
              name: dep,
              existing: existing.version,
              requirements: requirements,
              why: inner_why,
            )
          end
        end

        resolved = nil
        first_failure = nil

        found_any = false
        candidates = store.each(dep).select do |g|
          found_any = true
          g.satisfies?(requirements)
        end

        candidates.each do |g|
          result = gems_for_activation(store, activated_gems, g, why: inner_why, context: context)
          if result.is_a?(Exception)
            first_failure ||= result
          else
            resolved = result
            break
          end
        end

        if resolved
          new_gems += resolved
          resolved.each do |r|
            context[r.name] = r
          end
        elsif first_failure
          return first_failure
        else

          return Gel::Error::UnsatisfiedDependencyError.new(
            name: dep,
            was_locked: locked?,
            found_any: found_any,
            requirements: requirements,
            why: inner_why,
          )
        end
      end

      new_gems
    end
  end
end
