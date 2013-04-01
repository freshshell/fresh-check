#!/usr/bin/env ruby

require 'bundler/setup'
require 'fresh_api/directory'
require 'tmpdir'
require 'open-uri'

def directory_lines
  directory = FreshApi::Directory.new
  html = URI.parse('https://github.com/freshshell/fresh/wiki/Directory').read
  directory.load_github_wiki_page(html)
  directory.entries.map(&:code)
end

def fresh_repo_path
  File.dirname(__FILE__) + '/.fresh/source/freshshell/fresh'
end

def init_fresh_repo
  unless File.directory? fresh_repo_path
    FileUtils.mkdir_p File.dirname(fresh_repo_path)
    system "git clone https://github.com/freshshell/fresh #{Shellwords.escape fresh_repo_path}"
    raise unless $?.success?
  end
end

def readme_lines
  init_fresh_repo
  File.read(fresh_repo_path + '/README.markdown').split(/[\n`]/).grep(%r[^fresh [^ /]+/[^ ]+ [^ ]+]).reject { |line| line =~ /example/ }
end

def with_env(new_env)
  backup_env = {}
  new_env.each do |key, value|
    backup_env[key] = ENV[key]
    ENV[key] = value
  end
  yield
ensure
  backup_env.each do |key, value|
    ENV[key] = value
  end
end

def with_fresh_sandbox
  init_fresh_repo
  Dir.mktmpdir 'fresh_check' do |sandbox_dir|
    paths = {
      'HOME' => "#{sandbox_dir}/home",
      '_BIN' => "#{sandbox_dir}/bin",
      'PATH' => "#{sandbox_dir}/bin:/usr/bin:/bin",
      'FRESH_RCFILE' => "#{sandbox_dir}/freshrc",
      'FRESH_PATH' => "#{sandbox_dir}/fresh",
      'FRESH_LOCAL' => "#{sandbox_dir}/dotfiles"
    }
    dummy_filters = %w[erb gpg]

    FileUtils.mkdir_p paths.values_at('HOME', '_BIN', 'FRESH_PATH', 'FRESH_LOCAL')
    FileUtils.ln_s File.expand_path(File.dirname(__FILE__) + '/.fresh/source'), "#{paths['FRESH_PATH']}/source"

    FileUtils.ln_s "#{paths['FRESH_PATH']}/source/freshshell/fresh/bin/fresh", "#{paths['_BIN']}/fresh"
    dummy_filters.each do |name|
      FileUtils.ln_s `which true`.chomp, "#{paths['_BIN']}/#{name}"
    end

    with_env paths do
      Dir.chdir paths['HOME'] do
        yield
      end
    end
  end
end

def check_line(line)
  with_fresh_sandbox do
    File.open ENV['FRESH_RCFILE'], 'w' do |io|
      io.puts 'FRESH_NO_BIN_CHECK=true'
      io.puts line
    end
    output = `fresh 2>&1`
    $?.success? ? true : output
  end
end

def output_result(line, result)
  if result == true
    $stderr.puts "\e[1;32m\u2713\e[0m #{line}"
  else
    $stderr.puts "\e[1;31m\u2717\e[0m #{line}"
    $stdout.puts result.gsub(/^/, '    ')
  end
end

def output_progress(line)
  $stderr.write "\e[1;30m?\e[0m #{line}"
  $stderr.write "\e[0G"
end

if $0 == __FILE__
  (readme_lines + directory_lines).each do |line|
    output_progress line
    result = check_line line
    output_result line, result
  end
end
