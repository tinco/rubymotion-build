module Motion; module Project  
  module ReferencesMatcher
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
  end
end; end
