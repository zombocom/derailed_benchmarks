module DerailedBenchmarks
  class InGitPath
    attr_reader :path

    def initialize(path)
      @path = path
    end

    def description
      run!("git log --oneline --format=%B -n 1 HEAD | head -n 1")
    end

    def short_sha
      run!("git rev-parse --short HEAD")
    end

    def time_stamp_string
      run!("git log -n 1 --pretty=format:%ci") # https://stackoverflow.com/a/25921837/147390
    end

    def branch
      branch = run!("git rev-parse --abbrev-ref HEAD")
      branch == "HEAD" ? nil : branch
    end

    def checkout!(ref)
      run!("git checkout '#{ref}' 2>&1")
    end

    def time
      DateTime.parse(time_stamp_string)
    end

    def run(cmd)
      if Dir.pwd == path
        out = `#{cmd}`.strip
      else
        out = `cd #{path} && #{cmd}`.strip
      end
      out
    end

    def run!(cmd)
      out = run(cmd)
      raise "Error while running #{cmd.inspect}: #{out}" unless $?.success?
      out
    end
  end

  # Represents a specific commit in a git repo
  #
  # Can be used to get information from the commit or to check it out
  #
  # commit = GitCommit.new(path: "path/to/repo", ref: "6e642963acec0ff64af51bd6fba8db3c4176ed6e")
  # commit.short_sha # => "6e64296"
  # commit.checkout! # Will check out the current commit at the repo in the path
  class GitCommit
    attr_reader :ref, :description, :time, :short_sha, :log

    def initialize(path: , ref: , log_dir: Pathname.new("/dev/null"))
      @in_git_path = InGitPath.new(path)
      @ref = ref
      @log = log_dir.join("#{file_safe_ref}.bench.txt")

      Dir.chdir(path) do
        checkout!
        @description = @in_git_path.description
        @short_sha = @in_git_path.short_sha
        @time = @in_git_path.time
      end
    end

    alias :desc :description
    alias :file :log

    def checkout!
      @in_git_path.checkout!(ref)
    end

    private def file_safe_ref
      ref.gsub('/', ':')
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
  # You can pass in explicit REFs in an array:
  #
  #   ref_array = ["da748a59340be8b950e7bbbfb32077eb67d70c3c", "9b19275a592f148e2a53b87ead4ccd8c747539c9"]
  #   project = GitSwitchProject.new(path: "tmp/default_ruby", ref_array: ref_array)
  #
  #   puts project.commits.map(&:ref) == ref_array # => true
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

    def initialize(path: , ref_array: [], io: STDOUT, log_dir: nil)
      @path = Pathname.new(path)

      @in_git_path = InGitPath.new(@path.expand_path)

      raise "Must be a path with a .git directory '#{@path}'" if !@path.join(".git").exist?
      @io = io
      @commits = []
      log_dir = Pathname(log_dir || "/dev/null")

      expand_refs(ref_array).each do |ref|
        restore_branch_on_return(quiet: true) do
          @commits << GitCommit.new(path: @path, ref: ref, log_dir: log_dir)
        end
      end

      if (duplicate = @commits.group_by(&:short_sha).detect {|(k, v)| v.length > 1})
        raise "Duplicate SHA resolved #{duplicate[0].inspect}: #{duplicate[1].map {|c| "'#{c.ref}' => '#{c.short_sha}'"}.join(", ") } at #{@path}"
      end
    end

    def current_branch_or_sha
      branch_or_sha = @in_git_path.branch
      branch_or_sha ||= @in_git_path.short_sha
      branch_or_sha
    end

    def dirty?
      !clean?
    end

    # https://stackoverflow.com/a/3879077/147390
    def clean?
      @in_git_path.run("git diff-index --quiet HEAD --") && $?.success?
    end

    private def status(pattern: "*.gemspec")
      @in_git_path.run("git status #{pattern}")
    end

    def restore_branch_on_return(quiet: false)
      if dirty? && status.include?("gemspec")
        dirty_gemspec = true
        unless quiet
          @io.puts "Working tree at #{@path} is dirty, stashing. This will be popped on return"
          @io.puts "Bundler modifies gemspec files on git install, this is normal"
          @io.puts "Original status:\n#{status}"
        end
        @in_git_path.run!("git stash")
      end
      branch_or_sha = self.current_branch_or_sha
      yield
    ensure
      return unless branch_or_sha
      @io.puts "Resetting git dir of '#{@path.to_s}' to #{branch_or_sha.inspect}" unless quiet

      @in_git_path.checkout!(branch_or_sha)
      if dirty_gemspec
        out = @in_git_path.run!("git stash pop 2>&1")
        @io.puts "Popping stash of '#{@path.to_s}':\n#{out}" unless quiet
      end
    end

    # case ref_array.length
    # when >= 2
    #   returns original array
    # when 1
    #   returns the given ref plus the one before it
    # when 0
    #   returns the most recent 2 refs
    private def expand_refs(ref_array)
      return ref_array if ref_array.length >= 2

      @in_git_path.checkout!(ref_array.first) if ref_array.first

      branches_string = @in_git_path.run!("git log --format='%H' -n 2")
      ref_array = branches_string.split($/)
      return ref_array
    end
  end
end
