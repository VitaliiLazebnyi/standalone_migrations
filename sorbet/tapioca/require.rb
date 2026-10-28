# typed: true
# frozen_string_literal: true

# The gem is called activerecord, but its entry point is active_record; Tapioca needs it loaded to compile
# the RBIs of ActiveRecord and of everything ActiveRecord loads lazily.
require "active_record"
require "active_record/schema_dumper"
require "active_support/core_ext/string/filters"

# Loading ActiveSupport::Configurable prints a deprecation notice (Rails 8.1 deprecates it without
# replacement), and Tapioca loads every constant it finds while it compiles the RBIs. Neither this project
# nor any of its dependencies uses that module, so its autoload is removed (without loading it) before the
# RBIs are compiled.
ActiveSupport.__send__(:remove_const, :Configurable) if ActiveSupport.autoload?(:Configurable)
