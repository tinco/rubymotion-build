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
      parsed_files = @file_paths.map {|p| parse(p) }
      build_context = parsed_files.map {|p| determine_definitions_and_references(p) }

      # first we have to establish for each file which files it depends on

      consts_defined  = build_context.flat_map {|f| f[:definitions] }
      consts_referred = {}
      build_context.each do |f|
        consts_referred[f[:name]] = f[:references]
      end

      dependency = establish_dependencies(build_context)

      dependency
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
        add_definitions(definitions, f[:name], f[:definitions], "")
      end

      # for each reference in each file, we want to get the file that has it defined
      build_context.each do |f|
        references = f[:references]
        dependants[f[:name]] =
          references.map {|r| get_dependency(f[:name], definitions, r)}.compact.uniq.select{|r| r != f[:name] }
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

    def determine_definitions_and_references(file)
      definitions_and_references = scan(file[:parsed][1]) # [:program, [..] ]

      file.merge! definitions_and_references

      file
    end

    def scan(tree)
      # we want to match a module, a class, constant or method definition
      # and add those to definitions
      definitions = {}
      references = []

      tree.each do |sexp|
        definition, body = match_definition(sexp)
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
        next unless sexp
        found_references =
          match_class_inheritance(sexp) ||
          match_command(sexp) ||
          match_expression(sexp)

        next unless found_references

        found_references.each do |reference|
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
    def match_expression(sexp)
      # can a named scope be created inside an expression? if so
      # then this means we're going to have to track both at the
      # same time :(
      match_const_path(sexp) ||
        match_call(sexp) ||
        match_top_const(sexp) ||
        match_var_ref(sexp) ||
        match_assign(sexp) ||
        match_method_add_arg(sexp) ||
        match_method_add_block(sexp) ||
        match_array(sexp) ||
        match_opassign(sexp) ||
        match_def_references(sexp) || # todo this isn't really an expression, but we'll have to modify the definitions thing to explore scopes without names or something to remove this here
        [] # etc..
    end

    def match_def_references(sexp)
      # [:def,
      #   [:@ident, "initialize", [5, 8]],
      #   [:params, nil, nil, nil, nil, nil, nil, nil],
      #   [:bodystmt, [[:void_stmt]], nil, nil, nil]]
      if sexp && sexp[0] == :def
        params = sexp[2][1..-1] # Todo find consts in params
        body = sexp[3][1]
        body.map {|e| match_expression(e)}.flatten
      end
    end

    def match_assign(sexp)
      if sexp && sexp[0] == :assign
        match_expression(sexp[1]) + match_expression(sexp[2])
      end
    end

    def match_var_ref(sexp)
      # [:var_ref, [:@const, "Game", [5, 12]]]
      if sexp && sexp[0] == :var_ref
        if sexp[1][0] == :@const
          [] << sexp[1][1]
        end
      end
    end

    def match_top_const(sexp)
      # [:top_const_ref, [:@const, "Accessiblity", [3, 14]]]
      if sexp && sexp[0] == :top_const_ref
        [] << "::" + sexp[1][1]
      end
    end

    def match_call(sexp)
      if sexp && sexp[0] == :call
        match_expression(sexp[1]) # TODO continue implementation
      end
    end

    def match_method_add_arg(sexp)
      # ,[:method_add_arg,
        # [:call, [ ...]],
        # [:arg_paren, [:args_add_block, [[:var_ref,
      if sexp && sexp[0] == :method_add_arg
        result = match_expression(sexp[1])
        if sexp[2] && sexp[2][0] == :args_add_block
          result += sexp[2][1].map {|e| match_expression(e)}.flatten
        end
      end
      result
    end

    def match_method_add_block(sexp)
      # [:method_add_block,
      #   [:call, [ .. ] ]
        # [:brace_block, [:block_var, [:params, [[:@ident, "beer", [22, 22]]], ..], false], [[:method_add_arg, [:call, [:call, [:var_ref, [:@kw, "self", [22, 28]]], :".", [:@ident, "view", [22, 33]]], :".", [:@ident, "addAnnotation", [22, 38]]], [:arg_paren, [:args_add_block, [[:var_ref, [:@ident, "beer", [22, 52]]]], false]]]]]
      # ]
      if sexp && sexp[0] == :method_add_block
        result = match_expression(sexp[1])
        if sexp[2] && sexp[2][0] == :brace_block
          result += sexp[2][2].map {|e| match_expression(e)}.flatten
        end
      end
      result
    end

    # [:const_path_ref, [:var_ref, [:@const, "B1", [1, 0]]], [:@const, "B2", [1, 4]]]
    def match_const_path(sexp)
      if sexp && sexp[0] == :const_path_ref
        # TODO what if it somehow references a constant that's not part of the
        # const path?
        prefix = match_expression(sexp[1])
        suffix = sexp[2][1]
        [] << (prefix << suffix).join("::")
      end
    end

    def match_command(sexp)
      if sexp && sexp[0] == :command
        # TODO research what else can be in a command
        args = sexp[2]
        args[1].flat_map {|a| match_expression(a)}.compact
      end
    end

    def match_class_inheritance(sexp)
      if sexp && sexp.first == :class
        match_expression(sexp[2]) # TODO untested
      end
    end

    def match_array(sexp)
      if sexp && sexp[0] == :array
        sexp[1].flat_map {|a| match_expression(a)}.compact
      end
    end

    def match_definition(sexp)
      match_class_def(sexp) || match_module_def(sexp) || match_constant_def(sexp) || match_method_def(sexp)
    end

    def match_opassign(sexp)
      # [:opassign, [:var_field, [..], [:@op, "||=", [51, 29]], [:call, .. ]]]
      if sexp && sexp.first == :opassign
        match_expression(sexp[1]) + match_expression(sexp[3])
      end
    end

    def match_method_def(sexp)
      nil # todo
    end

    def match_class_def(sexp)
      # [:class, [:const_ref ... ], nil, ... ]
      if sexp && sexp.first == :class
        [] << resolve_const_ref(sexp[1]) << sexp[3][1]
      end
    end

    def match_module_def(sexp)
      # [:module, [:const_ref ... ], ... ]
      if sexp && sexp.first == :module
        [] << resolve_const_ref(sexp[1]) << sexp[2][1]
      end
    end

    def match_constant_def(sexp)
      if sexp && sexp.first == :assign &&
         sexp[1].first == :var_field &&
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

    def parse(file)
      {
        name: file,
        parsed: Ripper.sexp(File.read(file)),
        definitions: {},
        references: {}
      }
    end
  end
end; end
