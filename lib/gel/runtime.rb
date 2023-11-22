# frozen_string_literal: true

require_relative "../gel"

dir = ENV["GEL_STORE"] || "~/.local/gel"
dir = File.expand_path(dir)

unless Dir.exist?(dir)
  require_relative "util"
  Gel::Util.mkdir_p(dir)
end

dir = File.realpath(dir)

stores = {}
Gel::GodObject.store_set.each do |key|
  subdir = File.join(dir, key)
  Dir.mkdir(subdir) unless Dir.exist?(subdir)
  stores[key] = Gel::Store.new(subdir)
end
store = Gel::MultiStore.new(dir, stores)

Gel::GodObject.open(store)

if ENV["GEL_LOCKFILE"] && ENV["GEL_LOCKFILE"] != ""
  Gel::GodObject.activate(fast: true, output: $stderr)
end
