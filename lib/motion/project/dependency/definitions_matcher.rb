module Motion; module Project
  module DefinitionsMatcher
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
end; end
