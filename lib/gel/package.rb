# frozen_string_literal: true

require "zlib"
require "yaml"

require_relative "support/sha512"
require_relative "support/tar"
require_relative "vendor/ruby_digest"

module Gel
  class Package
    class Specification
      def initialize(inner)
        @inner = inner
      end

      def name
        @inner.name
      end

      def version
        @inner.version
      end

      def architecture
        @inner.architecture
      end

      def platform
        @inner.platform
      end

      def bindir
        @inner.bindir
      end

      def executables
        @inner.executables
      end

      def require_paths
        @inner.require_paths
      end

      def extensions
        @inner.extensions
      end

      def required_ruby_version
        @inner.required_ruby_version&.requirements&.map { |pair| pair.map(&:to_s) }
      end

      def runtime_dependencies
        h = {}
        @inner.dependencies.each do |dep|
          next unless dep.type == :runtime || dep.type.nil?
          req = dep.requirement || dep.version_requirements
          h[dep.name] = req.requirements.map { |pair| pair.map(&:to_s) }
        end
        h
      end
    end

    class YAMLLoader < ::YAML::ClassLoader::Restricted
      #--
      # Based on YAML.safe_load
      def self.load(yaml, filename)
        result = if Psych::VERSION < "3.1" # Ruby 2.5 & below
                   ::YAML.parse(yaml, filename)
                 else
                   ::YAML.parse(yaml, filename: filename)
                 end
        return unless result

        class_loader = self.new
        scanner      = ::YAML::ScalarScanner.new class_loader

        visitor = ::YAML::Visitors::ToRuby.new scanner, class_loader
        visitor.accept result
      end

      def initialize
        super(%w(Symbol Time Date), [])
      end

      def find(klass)
        case klass
        when "Gem::Specification"
          Gem_Specification
        when "Gem::Version"
          Gem_Version
        when "Gem::Version::Requirement", "Gem::Requirement"
          Gem_Requirement
        when "Gem::Platform"
          Gem_Platform
        when "Gem::Dependency"
          Gem_Dependency
        else
          super
        end
      end

      class Gem_Specification
        attr_accessor :architecture, :bindir, :executables, :name, :platform, :require_paths, :specification_version, :version, :dependencies, :extensions, :required_ruby_version
      end
      class Gem_Dependency
        attr_accessor :name, :requirement, :type, :version_requirements
      end
      class Gem_Platform; end
      Gem_Version = Gel::Support::GemVersion
      class Gem_Requirement
        attr_accessor :requirements
      end
    end

    def self.with_file(reader, filename, checksums)
      reader.seek(filename) do |stream|
        if checksums
          data = stream.read
          stream.rewind

          checksums.each do |type, map|
            calculated =
              case type
              when "SHA1"
                Gel::Vendor::RubyDigest::SHA1.hexdigest(data)
              when "SHA512"
                Gel::Support::SHA512.hexdigest(data)
              else
                next
              end
            raise "#{type} checksum mismatch on #{filename}" unless calculated == map[filename]
          end
        end

        yield stream
      end
    end

    # def self.verify_checksum(dir, filename, checksums)
    #   # Sometimes there are multiple checksums for a single file.
    #   # This feature only exists to mitigate corrupted gems, not for
    #   # security -- really it should have been a CRC32.
    #   # Anyway, in light of that, we try the faster algorithm first and
    #   # return before checking the slower of the two, if the first was present.
    #   {'SHA1' => '-sha1', 'SHA512' => '-sha512'}.each do |rubygems_algo, openssl_algo|
    #     if (expected_sum = checksums[rubygems_algo]&.[](filename))
    #       # Note: shasum on macOS burns about 23ms in setup time for nothing.
    #       # Openssl is much faster.
    #       out, err, stat = Open3.capture3("openssl", "dgst", "-r", openssl_algo, File.join(dir, filename))
    #       raise "openssl dgst failed: #{err}" unless stat.success?
    #       found_sum, _ = out.split(/\s+/, 2)
    #       raise "#{type} checksum mismatch on #{filename}" unless found_sum == expected_sum
    #       return
    #     end
    #   end
    # end

    def self.verify_checksums(dir, checksums)
      processes = []

      %w(metadata.gz data.tar.gz).each do |filename|
        {'SHA1' => '-sha1', 'SHA512' => '-sha512'}.each do |rubygems_algo, openssl_algo|
          if (expected_sum = checksums[rubygems_algo]&.[](filename))
            stdin, stdout, stderr, wait_thr = Open3.popen3("openssl", "dgst", "-r", openssl_algo, File.join(dir, filename))
            stdin.close
            processes << { out: stdout, err: stderr, wait_thr: wait_thr, expected_sum: expected_sum }
            break # no need to verify more than one for each file
          end
        end
      end

      processes.each do |process|
        out = process[:out].read
        process[:out].close
        err = process[:err].read
        process[:err].close
        raise "openssl dgst failed for #{filename}: #{err}" unless process[:wait_thr].value.success?

        found_sum, _ = out.split(/\s+/, 2)
        raise "checksum mismatch on #{filename}" unless found_sum.strip == process[:expected_sum]
      end
    end

    def self.extract(filename, receiver)
      if Gem.win_platform? || ENV["GEL_PURE_RUBY_TAR"]
        return extract_with_pure_ruby_tar(filename, receiver)
      end

      require "tmpdir"
      require "open3"
      Dir.mktmpdir do |dir|
        _, err, stat = Open3.capture3("tar", "-C", dir, "-xf", filename)
        raise "tar failed: #{err}" unless stat.success?

        if File.exist?(File.join(dir, 'checksums.yaml.gz'))
          # This feels ugly. There is a definitely a nicer way.
          yaml = File.open(File.join(dir, 'checksums.yaml.gz')) do |f|
            gz = Zlib::GzipReader.new(f)
            yaml = gz.read
            gz.close
            yaml
          end

          sums = if Psych::VERSION < "3.1" # Ruby 2.5 & below
            ::YAML.safe_load(yaml, [], [], false, "#{filename}:checksums.yaml.gz")
          else
            ::YAML.safe_load(yaml, filename: "#{filename}:checksums.yaml.gz")
          end

          verify_checksums(dir, sums)
          # We could also verify signatures. I guess.
        end

        # This feels ugly. There is a definitely a nicer way.
        yaml = File.open(File.join(dir, 'metadata.gz')) do |f|
          gz = Zlib::GzipReader.new(f)
          yaml = gz.read
          gz.close
          yaml
        end
        loaded = YAMLLoader.load(yaml, "#{filename}:metadata.gz")
        spec = Specification.new(loaded)

        return receiver.gem(spec) do |target|
          data_dir = File.join(dir, 'data')
          FileUtils.mkdir(data_dir)
          _, err, stat = Open3.capture3("tar", "-C", data_dir, "-xf", File.join(dir, 'data.tar.gz'))
          raise "tar failed: #{err}" unless stat.success?
          target.ingest(data_dir)
        end
      end
    end

    def self.extract_with_pure_ruby_tar(filename, receiver)
      File.open(filename) do |io|
        Gel::Support::Tar::TarReader.new(io) do |package_reader|
          sums = with_file(package_reader, "checksums.yaml.gz", nil) do |sum_stream|
            yaml = Zlib::GzipReader.new(sum_stream).read

            if Psych::VERSION < "3.1" # Ruby 2.5 & below
              ::YAML.safe_load(yaml, [], [], false, "#{filename}:checksums.yaml.gz")
            else
              ::YAML.safe_load(yaml, filename: "#{filename}:checksums.yaml.gz")
            end
          end

          spec = with_file(package_reader, "metadata.gz", sums) do |meta_stream|
            yaml = Zlib::GzipReader.new(meta_stream).read
            loaded = YAMLLoader.load(yaml, "#{filename}:metadata.gz")
            Specification.new(loaded)
          end or raise "no metadata.gz"

          return receiver.gem(spec) do |target|
            with_file(package_reader, "data.tar.gz", sums) do |data_stream|
              Gel::Support::Tar::TarReader.new(Zlib::GzipReader.new(data_stream)) do |data_reader|
                data_reader.each do |entry|
                  target.file(entry.full_name, entry, entry.header.mode)
                end
              end
              true
            end or raise "no data.tar.gz"
          end
        end
      end
    end
  end
end
