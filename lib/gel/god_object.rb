# frozen_string_literal: true

require_relative "load_path_manager"

class Gel::GodObject
  IGNORE_LIST = %w(bundler gel rubygems-update)
end

require_relative "god_object/stateless"
