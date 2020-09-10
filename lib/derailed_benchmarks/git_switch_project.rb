module DerailedBenchmarks
  # Represents a specific commit in a git repo
  #
  # Can be used to get information from the commit or to check it out
  #
  # commit = GitCommit.new(path: "path/to/repo", sha: "6e642963acec0ff64af51bd6fba8db3c4176ed6e")
  # commit.short_sha # => "6e64296"
  # commit.checkout! # Will check out the current commit at the repo in the path
  class GitCommit
    attr_reader :sha, :description, :time, :short_sha, :log

    def initialize(path: , sha: , log_dir: Pathname.new("/dev/null"))
      @sha = sha
      @path = path
      @meta = {}
      @log = nil

      Dir.chdir(@path) do
        checkout!
        @description = run!("git log --oneline --format=%B -n 1 HEAD | head -n 1")
        @short_sha   = run!("git rev-parse --short HEAD")
        @log         = log_dir.join("#{file_safe_sha}.bench.txt")

        time_stamp  = run!("git log -n 1 --pretty=format:%ci") # https://stackoverflow.com/a/25921837/147390
        @time = DateTime.parse(time_stamp)
      end
    end

    alias :desc :description
    alias :file :log

    def checkout!
      run!("cd #{@path} && git checkout '#{sha}' 2>&1")
    end

    private def file_safe_sha
      sha.gsub('/', ':')
    end

    private def run!(cmd)
      out = `#{cmd}`.strip
      raise "Error while running #{cmd.inspect}: #{out}" unless $?.success?
      out
    end
  end

  # Wraps two or more git commits in a specific location
  #
  # Returns an array of GitCommit objects that can be used to manipulate
  # and checkout the repo
  #
  # Example:
  #
  #   `git clone https://sharpstone/default_ruby tmp/default_ruby`
  #
  #   project = GitSwitchProject.new(path: "tmp/default_ruby")
  #
  # By default it will represent the last two commits:
  #
  #   project.commits.length # => 2
  #
  # You can pass in explicit SHAs in an array:
  #
  #   sha_array = ["da748a59340be8b950e7bbbfb32077eb67d70c3c", "9b19275a592f148e2a53b87ead4ccd8c747539c9"]
  #   project = GitSwitchProject.new(path: "tmp/default_ruby", sha_array: sha_array)
  #
  #   puts project.commits.map(&:sha) == sha_array # => true
  #
  #
  # It knows the current branch or sha:
  #
  #    `cd tmp/ruby && git checkout -b mybranch`
  #    project.current_branch_or_sha #=> "mybranch"
  #
  # It can be used for safely wrapping checkouts to ensure the project returns to it's original branch:
  #
  #    project.restore_branch_on_return do
  #      project.commits.first.checkout!
  #      project.current_branch_or_sha # => "da748a593"
  #    end
  #
  #    project.current_branch_or_sha # => "mybranch"
  class GitSwitchProject
    attr_reader :commits

    def initialize(path: , sha_array: [], io: STDOUT, log_dir: nil)
      @path = Pathname.new(path)

      raise "Must be a path with a .git directory '#{@path}'" if !@path.join(".git").exist?
      @io = io
      @commits = []
      log_dir = Pathname(log_dir || "/dev/null")

      expand_shas(sha_array).each do |sha|
        restore_branch_on_return(quiet: true) do
          @commits << GitCommit.new(path: @path, sha: sha, log_dir: log_dir)
        end
      end
    end

    def current_branch_or_sha
      out = run!("cd #{@path} && git rev-parse --abbrev-ref HEAD")
      out == "HEAD" ? run!("cd #{@path} && git rev-parse --short HEAD") : out
    end

    def dirty?
      !clean?
    end

    # https://stackoverflow.com/a/3879077/147390
    def clean?
      `cd #{@path} && git diff-index --quiet HEAD --` && $?.success?
    end

    private def status(pattern: "*.gemspec")
      run!("cd #{@path} && git status #{pattern}")
    end

    def restore_branch_on_return(quiet: false)
      if dirty? && status.include?("gemspec")
        dirty_gemspec = true
        unless quiet
          @io.puts "Working tree at #{@path} is dirty, stashing. This will be popped on return"
          @io.puts "Bundler modifies gemspec files on git install, this is normal"
          @io.puts "Original status:\n#{status}"
        end
        run!("cd #{@path} && git stash")
      end
      sha_ish = self.current_branch_or_sha
      yield
    ensure
      return unless sha_ish
      @io.puts "Resetting git dir of '#{@path.to_s}' to #{sha_ish.inspect}" unless quiet
      run!("cd #{@path} && git checkout '#{sha_ish}' 2>&1")
      if dirty_gemspec
        out = run!("cd #{@path} && git stash pop 2>&1")
        @io.puts "Popping stash of '#{@path.to_s}':\n#{out}" unless quiet
      end
    end

    # case sha_array.length
    # when >= 2
    #   returns original array
    # when 1
    #   returns the given sha plus the one before it
    # when 0
    #   returns the most recent 2 shas
    private def expand_shas(sha_array)
      return sha_array if sha_array.length >= 2

      run!("cd #{@path} && git checkout '#{sha_array.first}' 2>&1") if sha_array.first

      branches_string = run!("cd #{@path} && git log --format='%H' -n 2")
      sha_array = branches_string.split($/)
      return sha_array
    end

    private def run!(cmd)
      out = `#{cmd}`.strip
      raise "Error while running #{cmd.inspect}: #{out}" unless $?.success?
      out
    end
  end
end
