# encoding: utf-8

require 'motion/project/dependency/definitions_matcher'
require 'motion/project/dependency/references_matcher'

module Motion; module Project
  # ConstantsAnalyzer is used to find constant definitions and references in a Ruby file
  class ConstantsAnalyzer
    include DefinitionsMatcher, ReferencesMatcher

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
  end
end; end
