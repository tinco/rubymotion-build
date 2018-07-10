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

    # ConstantsAnalyzer is used to find constant definitions and references in a Ruby file
    class ConstantsAnalyzer
      attr_reader :file_name, :parsed, :definitions, :references
      def initialize(file_name)
        @file_name = file_name
        @parsed = []
        @definitions = {}
        @references = {}
      end

      def run
        parse
        determine_definitions_and_references
      end

      def parse
        @parsed = Ripper.sexp(File.read(file_name))
      end

      def determine_definitions_and_references
        tree = parsed[1] # [:program, [..] ]
        definitions_and_references = scan(tree)
        @definitions = definitions_and_references[:definitions]
        @references = definitions_and_references[:references]
      end

      private

      def scan(tree)
        # we want to match a module, a class, constant or method definition
        # and add those to definitions
        definitions = {}
        references = []

        tree.each do |sexp|
          definition, body = match_definitions(sexp)
          if definition
            definitions[definition] = {}

            if body
              result = scan(body)
              definitions[definition] = result[:definitions]
              result[:references].each do |r|
                # Each reference is a tuple of the name of the reference, and
                # its named scope
                references << [r[0], r[1].unshift(definition)]
              end
            end
          end
        end

        # we want to match constants and ident references and add those to references
        tree.each do |sexp|
          match_references(sexp).each do |reference|
            references << [reference,[]] if reference
          end
        end

        # inside those matches we want to recurse to find more definitions and references
        {
          definitions: definitions,
          references: references
        }
      end

      # Note these will have to be expressions that can be evaluated at compile time
      def match_references(sexp)
        return [] unless sexp.is_a?(Array)

        case sexp.first
        when :const_path_ref
          match_const_path(sexp)
        when :call
          match_call(sexp)
        when :top_const_ref
          match_top_const(sexp)
        when :var_ref
          match_var_ref(sexp)
        when :assign
          match_assign(sexp)
        when :method_add_arg
          match_method_add_arg(sexp)
        when :method_add_block
          match_method_add_block(sexp)
        when :array
          match_array(sexp)
        when :opassign
          match_opassign(sexp)
        when :def
          # TODO this isn't really an expression, but we'll have to modify the
          # definitions thing to explore scopes without names or something to
          # remove this here
          match_def_references(sexp)
        when :command
          match_command(sexp)
        when :class
          match_class_inheritance(sexp)
        when :void_stmt, :field, :var_field, :@int, :vcall, :if, :string_literal,
             :binary, :aref, :fcall
          [] # TODO implement most of these
        else
          warn "Don't know how to find const_ref in: #{sexp.first}"
          []
        end
      end

      def match_def_references(sexp)
        # [:def,
        #   [:@ident, "initialize", [5, 8]],
        #   [:params, nil, nil, nil, nil, nil, nil, nil],
        #   [:bodystmt, [[:void_stmt]], nil, nil, nil]]
        params = sexp[2][1..-1] # Todo find consts in params
        body = sexp[3][1]
        body.map {|e| match_references(e)}.flatten
      end

      def match_assign(sexp)
        match_references(sexp[1]) + match_references(sexp[2])
      end

      def match_var_ref(sexp)
        # [:var_ref, [:@const, "Game", [5, 12]]]
        if sexp[1][0] == :@const
          [] << sexp[1][1]
        else
          # Are there other cases?
          []
        end
      end

      def match_top_const(sexp)
        # [:top_const_ref, [:@const, "Accessiblity", [3, 14]]]
        [] << "::" + sexp[1][1]
      end

      def match_call(sexp)
        match_references(sexp[1]) # TODO continue implementation
      end

      def match_method_add_arg(sexp)
        # [:method_add_arg,
        #   [:call, [ ...]],
        #   [:arg_paren, [:args_add_block, [[:var_ref,
        result = match_references(sexp[1])
        if sexp[2] && sexp[2][0] == :args_add_block
          result += sexp[2][1].map {|e| match_references(e)}.flatten
        end
        result
      end

      def match_method_add_block(sexp)
        # [:method_add_block,
        #   [:call, [ .. ] ]
          # [:brace_block, [:block_var, [:params, [[:@ident, "beer", [22, 22]]], ..], false], [[:method_add_arg, [:call, [:call, [:var_ref, [:@kw, "self", [22, 28]]], :".", [:@ident, "view", [22, 33]]], :".", [:@ident, "addAnnotation", [22, 38]]], [:arg_paren, [:args_add_block, [[:var_ref, [:@ident, "beer", [22, 52]]]], false]]]]]
        # ]
        result = match_references(sexp[1])
        if sexp[2] && sexp[2][0] == :brace_block
          result += sexp[2][2].map {|e| match_references(e)}.flatten
        end
        result
      end

      # [:const_path_ref, [:var_ref, [:@const, "B1", [1, 0]]], [:@const, "B2", [1, 4]]]
      def match_const_path(sexp)
        # TODO what if it somehow references a constant that's not part of the
        # const path?
        prefix = match_references(sexp[1])
        suffix = sexp[2][1]
        [] << (prefix << suffix).join("::")
      end

      def match_command(sexp)
        # TODO research what else can be in a command
        args = sexp[2]
        args[1].flat_map {|a| match_references(a)}.compact
      end

      def match_class_inheritance(sexp)
        match_references(sexp[2]) # TODO untested
      end

      def match_array(sexp)
        sexp[1].flat_map {|a| match_references(a)}.compact
      end

      def match_opassign(sexp)
        # [:opassign, [:var_field, [..], [:@op, "||=", [51, 29]], [:call, .. ]]]
        match_references(sexp[1]) + match_references(sexp[3])
      end

      def match_definitions(sexp)
        return [] unless sexp.is_a?(Array)

        case sexp.first
        when :class
          match_class_def(sexp)
        when :module
          match_module_def(sexp)
        when :assign
          match_constant_def(sexp)
        when :def
          match_method_def(sexp)
        when :void_stmt
          []
        else
          warn "Don't know how to find definition for #{sexp.first}"
          []
        end
      end


      def match_method_def(sexp)
        nil # todo
      end

      def match_class_def(sexp)
        # [:class, [:const_ref ... ], nil, ... ]
        [] << resolve_const_ref(sexp[1]) << sexp[3][1]
      end

      def match_module_def(sexp)
        # [:module, [:const_ref ... ], ... ]
        [] << resolve_const_ref(sexp[1]) << sexp[2][1]
      end

      def match_constant_def(sexp)
        if sexp[1].first == :var_field &&
           sexp[1][1].first == :@const
           [] << sexp[1][1][1]
        end
      end

      def resolve_const_ref(sexp)
        if sexp[0] == :const_ref
          # [:const_ref, [:@const, "View", [1, 6]]]
          sexp[1][1]
        else
          raise "name not a const_ref"
        end
      rescue
        puts "Could not resolve name: #{ sexp.inspect }"
      end
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
