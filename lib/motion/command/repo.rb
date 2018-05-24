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

require 'uri'

module Motion; class Command
  class Repo < Command
    self.summary = 'Create a support ticket.'
    # TODO make more elaborate
    # self.description = '...'

    def run
      root_directory = File.expand_path(File.join("~", '.rubymotion'))
      command_directory = File.expand_path(File.join("~", '.rubymotion/rubymotion-command'))
      templates_directory = File.expand_path(File.join("~", '.rubymotion/rubymotion-templates'))

      begin
        `mkdir #{root_directory}` unless File.directory?(root_directory)

        unless File.directory?(templates_directory)
          puts "Cloning RubyMotion templates. Feel free to browse #{templates_directory} to see how they're built."
          `git clone https://github.com/amirrajan/rubymotion-templates #{templates_directory}`
        else
          Dir.chdir(templates_directory) do
            `git pull`
          end
        end

        unless File.directory?(command_directory)
          puts "Cloning RubyMotion templates. Feel free to browse #{command_directory} to see how they're built."
          `git clone https://github.com/amirrajan/rubymotion-command #{command_directory}`
        else
          Dir.chdir(command_directory) do
            `git pull`
          end
        end
      rescue => exception
        puts "=========================================================================================="
        puts "#{exception}"
        puts "Retrieval of community templates from https://github.com/amirrajan/rubymotion-templates didn't work. Skipping for now."
        puts "=========================================================================================="
        return false
      end
    end
  end
end; end
