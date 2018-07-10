# encoding: utf-8

# Copyright (c) 2012, HipByte SPRL and contributors
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

require 'motion/project/dependency/constants_analyzer'

module Motion; module Project
  class ExperimentalDependency
    begin
      require 'ripper'
    rescue LoadError => err
      App.warn("Please use newer Ruby instead of Ruby v1.8.x for build process.")
      raise err
    end

    @file_paths = []

    def initialize(paths, dependencies)
      @file_paths = paths.flatten.sort
      @dependencies = dependencies
      @external_references = {}
    end

    def cyclic?(dependencies, def_path, ref_path)
      deps = dependencies[def_path]

      if deps
        if deps.include?(ref_path)
          return true
        end
        deps.each do |file|
          return true if cyclic?(dependencies, file, ref_path)
        end
      end

      false
    end

    def run
      analyzers = @file_paths.map {|f| ConstantsAnalyzer.new(f) }
      analyzers.each(&:run)
      establish_dependencies(analyzers)
    end

    def run_debug
      analyzers = @file_paths.map {|f| ConstantsAnalyzer.new(f) }
      analyzers.each(&:run)
      dependency = establish_dependencies(analyzers)

      consts_defined = Hash[analyzers.map {|a| [a.file_name, a.definitions]}]
      consts_referred = {}
      analyzers.each do |a|
        a.references.each do |r|
          consts_referred[r] ||= []
          consts_referred[r] << a.file_name
        end
      end

      {
        consts_defined: consts_defined,
        consts_referred: consts_referred,
        dependency: dependency
      }
    end

    # TODO move to config.rb (or something..)
    def resolve_order(dependants)
      # we sort by number of dependencies
      dependants.sort! {|f1, f2| f1[:dependencies].length <=> f2[:dependencies].length }
      # and create a list that will contain the final order
      build_order = []
      while !dependants.empty?
        # we loop over the ordered files, if a file has no dependencies that
        # are not in the final order, we add that file to the final order
        resolved, dependants = dependants.partition do |dependant|
          dependant[:dependencies].all? {|dependency| build_order.include? dependency}
        end
        # if we loop twice over the same list, we raise an exception that a
        # circular dependency exists
        if resolved.empty?
          raise "Circular dependency found: \n#{dependants.inspect}\nBuild order: #{build_order.inspect}"
        else
          build_order += resolved.map {|d| d[:name]}
        end
      end

      build_order
    end

    def establish_dependencies(build_context)
      definitions = {}
      dependants = {}

      # we make a Hash of each definition, to the file it is defined in
      build_context.each do |f|
        add_definitions(definitions, f.file_name, f.definitions, "")
      end

      # for each reference in each file, we want to get the file that has it defined
      build_context.each do |f|
        references = f.references
        dependants[f.file_name] =
          references.map {|r| get_dependency(f.file_name, definitions, r)}.compact.uniq.select{|r| r != f.file_name }
      end

      dependants.keep_if {|_,v| !v.empty? }

      dependants
    end

    private

    def get_dependency(file_name, definitions, reference)
      name, nesting = reference
      if name.start_with? "::"
        result = definitions[name]
        # TODO refactor so this does not need file name
        if result.nil?
          @external_references[name] ||= []
          @external_references[name] << file_name
        end
        return result
      end

      found = false
      prefix = ""
      loop do
        fullname = prefix + "::" + name
        result = definitions[fullname]
        return result if result
        if nesting.empty?
          # TODO refactor so this does not need file name
          @external_references[name] ||= []
          @external_references[name] << file_name
          return nil
        end
        prefix += "::" + nesting.shift
      end

      raise "Could not find reference #{name}"
    end

    def add_definitions(definitions, filename, new_definitions, prefix)
      new_definitions.each do |name, nested|
        fullname = prefix + "::" + name
        definitions[fullname] = filename # TODO multiple file definitions
        add_definitions(definitions, filename, nested, fullname)
      end
    end
  end
end; end
