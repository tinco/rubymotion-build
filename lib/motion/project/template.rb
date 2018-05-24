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

require 'motion/error'

require 'erb'
require 'fileutils'
require 'yaml'

module Motion; module Project
  class CommunityTemplates
  end

  class Template
    DefaultTemplate = 'ios'

    # for ERB
    attr_reader :name

    offline_templates = File.expand_path(File.join(__FILE__, '../template'))
    template_git_directory = File.expand_path(File.join("~", '.rubymotion/rubymotion-templates'))
    template_directory = File.expand_path(File.join("~", '.rubymotion/rubymotion-templates/motion/project/template'))

    if ENV['RUBYMOTION_TEMPLATES_OVERRIDE']
      puts "=========================================================================================="
      puts "RubyMotion templates path has been overridden to: #{ENV['RUBYMOTION_TEMPLATES_OVERRIDE']}."
      puts "=========================================================================================="
      Paths = [ENV['RUBYMOTION_TEMPLATES_OVERRIDE']]
    else
      if File.directory?(template_git_directory)
        Paths = [template_directory]
      else
        puts "=========================================================================================="
        puts "WARNING: Using offline templates. Run `motion repo` to download the latest templates."
        puts "=========================================================================================="
        Paths = [offline_templates]
      end
    end

    Paths << File.expand_path(File.join(ENV['HOME'], 'Library/RubyMotion/template'))

    # Templates from RubyMotion gems.
    if defined?(Gem) and defined?(Gem::Specification) and Gem::Specification.respond_to?(:each)
      Gem::Specification.each do |spec|
        if spec.respond_to?(:metadata) and path = spec.metadata['rubymotion_template_dir']
          Paths << File.join(spec.gem_dir, path)
        end
      end
    end

    # TODO Caching these and making it based on the Paths constant makes it
    #      less simple to register plugin templates, because you cannot add
    #      them to the Paths constant and ensure this method will return those
    #      newly registered templates either. The only nice way atm to register
    #      them is to add them directly to this cached `@all_templates` var.
    #      For instance, from the Joybox plugin:
    #
    # require 'motion/project/template'
    # Dir.glob(File.expand_path('../../template/joybox-*', __FILE__)).each do |template_path|
    #   Motion::Project::Template.all_templates[File.basename(template_path)] = template_path
    # end
    #
    def self.all_templates
      @all_templates ||= begin
        h = {}
        Paths.map { |path| Dir.glob(path + '/*') }.flatten.select { |x| !x.match(/^\./) and File.directory?(x) }.each do |template_path|
          h[File.basename(template_path)] = template_path
        end
        h
      end
    end

    def self.all_templates_description
      all_templates.keys.sort.map do |t|
        template = (t == DefaultTemplate) ? "#{t} (default)" : t
        template = "  * #{template}"
        metadata_file = File.join(all_templates[t], "metadata.yaml")
        begin
          if(File.exist?(metadata_file))
            template += "\n" + YAML.load(File.read(metadata_file)).to_yaml.split("\n").map { |l| "    " + l }.join("\n")
          end
        rescue => exception
          puts "=========================================================================================="
          puts "#{exception}"
          puts "Unable to parse metadata from template: #{t}."
          puts "=========================================================================================="
        end
        template += "\n"
      end.join('')
    end

    # TODO This seems to be unused.
    Templates = Paths.map { |path| Dir.glob(path + '/*') }.flatten.select { |x| !x.match(/^\./) and File.directory?(x) }.map { |x| File.basename(x) }

    def initialize(app_name, template_name)
      @name = @app_name = app_name
      @template_name = template_name.to_s
      repository = Repository.new(@template_name)

      if repository.exist?
        repository.clone
        @template_name = repository.name
      end

      @template_directory = self.class.all_templates[@template_name]
      unless @template_directory
        desc = "Cannot find template `#{@template_name}' in:\n\n"
        desc << Paths.map { |x| "  * #{x}\n" }.join('')
        desc << "\nAvailable templates:\n\n"
        desc << self.class.all_templates_description
        raise InformativeError, desc
      end

      unless app_name.match(/^[\w\s-]+$/)
        raise InformativeError, "Invalid project name."
      end

      if File.exist?(app_name)
        raise InformativeError, "Directory `#{app_name}' already exists"
      end
    end

    def generate
      App.log 'Create', @app_name
      FileUtils.mkdir(@app_name)

      Dir.chdir(@app_name) do
        create_directories()
        create_files()
      end
    end

    private

    def template_directory
      @template_directory
    end

    def create_directories
      template_files = File.join(template_directory, 'files')
      Dir.glob(File.join(template_files, "**/")).each do |dir|
        dir.sub!("#{template_files}/", '')
        dir = replace_file_name(dir)
        FileUtils.mkdir_p(dir) if dir.length > 0
      end
    end

    def create_files
      template_files = File.join(template_directory, 'files')
      Dir.glob(File.join(template_files, "**/*"), File::FNM_DOTMATCH).each do |src|
        dest = src.sub("#{template_files}/", '')
        next if File.directory?(src)
        next if dest.include?(".DS_Store")

        dest = replace_file_name(dest)
        if dest =~ /(.+)\.erb$/
          App.log 'Create', "#{@app_name}/#{$1}"
          File.open($1, "w") { |io|
            io.print ERB.new(File.read(src)).result(binding)
          }
        else
          App.log 'Create', "#{@app_name}/#{dest}"
          FileUtils.cp(src, dest)
        end
      end
    end

    def replace_file_name(file_name)
      file_name = file_name.gsub("{name}", "#{@name}")
      file_name
    end

    class Repository
      attr_reader :name

      def initialize(template)
        @url = template
        @name = begin
          # Extract repo name from HTTP, SSH or Git URLs:
          case template
          when /\w+:\/\/.+@*[\w\d\.]+\/.+\/(.+).git/i, /git@.+:.+\/(.+)\.git/i
            $1
          end
        end
      end

      def exist?
        @name != nil
      end

      def clone
        path = File.expand_path(File.join(ENV['HOME'], 'Library/RubyMotion/template', @name))
        App.log 'Template', "Cloning #{@name} template"
        git_clone(path)
      end

      private

      def git_clone(path)
        if File.exist?(path)
          # directory exists just do a pull
          App.log 'Template', "#{@name} already exists, performing a pull"
          system("git --work-tree=#{path} --git-dir=#{path}/.git pull origin master")
        else
          # no directory exists so clone
          result = system("git clone #{@url} #{path}")
          unless result
            App.log 'Template', "Unable to clone #{@url}"
          end
        end
      end
    end
  end

end; end
