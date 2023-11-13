# frozen_string_literal: true

class Gel::StoreGem
  @compatibility = Hash.new do |h, k|
    Gel::Support::GemRequirement.new(k).satisfied_by?(Gel::Support::GemVersion.new(RUBY_VERSION))
  end

  def self.compatible_ruby?(requirements)
    @compatibility[requirements]
  end

  EXTENSION_SUBDIR_TOKEN = ".."

  attr_reader :root, :name, :version, :extensions, :info

  def initialize(root, name, version, extensions, info)
    @root = root
    @name = name
    @version = version
    @extensions = extensions unless extensions && extensions.empty?
    @info = info
  end

  def ==(other)
    other.class == self.class && @name == other.name && @version == other.version
  end

  def hash
    @name.hash ^ @version.hash
  end

  def satisfies?(requirements)
    requirements.satisfied_by?(gem_version)
  end

  def compatible_ruby?
    # This will recalculate when false, but that's fine: the calculation
    # is itself cached, and we only really care about keeping the true
    # case fast.

    @compatible_ruby ||=
      !@info[:ruby] ||
        self.class.compatible_ruby?(@info[:ruby])
  end

  def require_paths
    paths = _require_paths.map { |reqp| "#{root}/#{reqp}" }
    paths << extensions if extensions
    raise(paths.inspect) unless paths.all? { |path| path.is_a?(String) }
    paths
  end

  def relative_require_paths
    paths = _require_paths.dup
    paths << relative_extensions if extensions
    paths
  end

  def relative_extensions
    Gel::Util.relative_path(root, extensions)
  end

  def bindir
    @info[:bindir] || "bin"
  end

  def dependencies
    @info[:dependencies]
  end

  def executables
    @info[:executables]
  end

  def path(file, subdir = nil)
    if subdir == EXTENSION_SUBDIR_TOKEN && extensions
      "#{extensions}/#{file}"
    else
      subdir ||= _default_require_path
      "#{root}/#{subdir}/#{file}"
    end
  end

  def entries_for_lib(name)
    dual_require_paths do |path, subdir|
      Gel::Util.loadable_files(path, name).each do |match_file|
        _match_name, match_ext = Gel::Util.split_filename_for_require(match_file)
        yield subdir, match_ext
      end
    end
  end

  def libs
    dual_require_paths do |path, subdir|
      Gel::Util.loadable_files(path).each do |file|
        basename, ext = Gel::Util.split_filename_for_require(file)
        yield basename, subdir, ext
      end
    end
  end

  private

  def gem_version
    @gem_version ||= Gel::Support::GemVersion.new(version)
  end

  def _require_paths
    @info[:require_paths]
  end

  def dual_require_paths
    is_first = true
    _require_paths.each do |reqp|
      yield "#{root}/#{reqp}", is_first ? nil : reqp
      is_first = false
    end
    if extensions
      yield extensions, EXTENSION_SUBDIR_TOKEN
    end
  end

  def _default_require_path
    _require_paths.first
  end
end
