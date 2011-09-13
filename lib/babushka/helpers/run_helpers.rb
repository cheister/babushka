module Babushka
  module RunHelpers
    include LogHelpers
    include ShellHelpers
    include PathHelpers

    def hostname
      shell 'hostname -f'
    end

    def rake cmd, &block
      sudo "rake #{cmd} RAILS_ENV=#{var :app_env}", :as => var(:username), &block
    end

    def bundle_rake cmd, &block
      cd var(:rails_root) do
        shell "bundle exec rake #{cmd} --trace RAILS_ENV=#{var :app_env}", :as => var(:username), :log => true, &block
      end
    end

    def check_file file_name, method_name
      File.send(method_name, file_name).tap {|result|
        log_error "#{file_name} failed #{method_name.to_s.sub(/[?!]$/, '')} check." unless result
      }
    end

    def grep pattern, file
      if (path = file.p).exists?
        output = if pattern.is_a? String
          path.readlines.select {|l| l[pattern] }
        elsif pattern.is_a? Regexp
          path.readlines.grep pattern
        end
        output unless output.blank?
      end
    end

    def change_line line, replacement, filename
      path = filename.p

      log "Patching #{path}"
      shell "cat > #{path}", :as => path.owner, :input => path.readlines.map {|l|
        l.gsub(/^(\s*)(#{Regexp.escape(line)})/, "\\1# #{edited_by_babushka}\n\\1# was: \\2\n\\1#{replacement}")
      }.join("")
    end

    def insert_into_file insert_before, path, lines, opts = {}
      opts.defaults! :comment_char => '#', :insert_after => nil
      nlines = lines.split("\n").length
      before, after = path.p.readlines.cut {|l| l.strip == insert_before.strip }

      log "Patching #{path}"
      if after.empty? || (opts[:insert_after] && before.last.strip != opts[:insert_after].strip)
        log_error "Couldn't find the spot to write to in #{path}."
      else
        shell "cat > #{path}", :as => path.owner, :sudo => !File.writable?(path), :input => [
          before,
          added_by_babushka(nlines).start_with(opts[:comment_char] + ' ').end_with("\n"),
          lines.end_with("\n"),
          after
        ].join
      end
    end

    def change_with_sed keyword, from, to, file
      # Remove the incorrect setting if it's there
      shell("#{sed} -ri 's/^#{keyword}\s+#{from}//' #{file}", :sudo => !File.writable?(file))
      # Add the correct setting unless it's already there
      grep(/^#{keyword}\s+#{to}/, file) or shell("echo '#{keyword} #{to}' >> #{file}", :sudo => !File.writable?(file))
    end

    def sed
      Base.host.linux? ? 'sed' : 'gsed'
    end

    def append_to_file text, file, opts = {}
      shell %Q{echo "\n# #{added_by_babushka(text.split("\n").length)}\n#{text.gsub('"', '\"')}" >> #{file}}, opts
    end

    def _by_babushka
      "by babushka-#{VERSION} at #{Time.now}"
    end
    def edited_by_babushka
      "This line edited #{_by_babushka}"
    end
    def added_by_babushka nlines
      if nlines == 1
        "This line added #{_by_babushka}"
      else
        "These #{nlines} lines added #{_by_babushka}"
      end
    end

    def babushka_config? path
      if !path.p.exists?
        unmet "the config hasn't been generated yet"
      elsif !grep(/Generated by babushka/, path)
        unmet "the config needs to be regenerated"
      else
        true
      end
    end

    def yaml path
      require 'yaml'
      YAML.load_file path.p
    end

    def render_erb erb, opts = {}
      if (path = erb_path_for(erb)).nil?
        log_error "If you use #render_erb within a dynamically defined dep, you have to give the full path to the erb template."
      elsif !File.exists?(path) && !opts[:optional]
        log_error "Couldn't find erb to render at #{path}."
      elsif File.exists?(path)
        Renderable.new(opts[:to]).render(path, opts.merge(:context => self)).tap {|result|
          if result
            log "Rendered #{opts[:to]}."
          else
            log_error "Couldn't render #{opts[:to]}."
          end
        }
      end
    end

    def erb_path_for erb
      if erb.to_s.starts_with? '/'
        erb # absolute path
      elsif load_path
        File.dirname(load_path) / erb # directory this dep is in, plus relative path
      end
    end

    def log_and_open message, url
      log "#{message} Hit Enter to open the download page.", :newline => false
      read_from_prompt ' '
      shell "open #{url}"
    end

    def mysql cmd, username = 'root', include_password = true
      password_segment = "--password='#{var :db_password}'" if include_password
      shell "echo \"#{cmd.gsub('"', '\"').end_with(';')}\" | mysql -u #{username} #{password_segment}"
    end
  end
end
