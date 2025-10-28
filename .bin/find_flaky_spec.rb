#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'pathname'

class FlakySpecFinder
  RED = "\e[31m"
  GREEN = "\e[32m"
  YELLOW = "\e[33m"
  RESET = "\e[0m"
  SPINNER_FRAMES = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']

  def initialize(spec_path_with_line)
    @spec_path_with_line = spec_path_with_line
    @spec_path, @line_number = parse_spec_input(spec_path_with_line)
    @spec_dir = File.dirname(@spec_path)
    @rails_root = find_rails_root(@spec_path)
    @spinner_index = 0
  end

  def call
    show_banner
    puts "Target spec: #{@spec_path}:#{@line_number}"
    puts "Rails root: #{@rails_root}"
    puts "=" * 80
    puts

    return unless verify_target_spec_exists
    return unless verify_spec_passes_in_isolation

    if spec_passes_with_same_file?
      success("\n✓ Spec still passes when run with all specs in same file")
      info("Searching across all other spec files...")
      find_problematic_file
    else
      failure("\n✗ Spec fails when run with specs in same file")
      info("Searching within the same file...")
      find_problematic_spec_in_file(@spec_path)
    end
  end

  private

  def show_banner
    puts
    puts "▄████  █    ██   █  █▀ ▀▄    ▄        ▄▄▄▄▄   █ ▄▄  ▄███▄   ▄█▄        ▄████  ▄█    ▄   ██▄   ▄███▄   █▄▄▄▄"
    puts "█▀   ▀ █    █ █  █▄█     █  █        █     ▀▄ █   █ █▀   ▀  █▀ ▀▄      █▀   ▀ ██     █  █  █  █▀   ▀  █  ▄▀"
    puts "█▀▀    █    █▄▄█ █▀▄      ▀█       ▄  ▀▀▀▀▄   █▀▀▀  ██▄▄    █   ▀      █▀▀    ██ ██   █ █   █ ██▄▄    █▀▀▌ "
    puts "█      ███▄ █  █ █  █     █         ▀▄▄▄▄▀    █     █▄   ▄▀ █▄  ▄▀     █      ▐█ █ █  █ █  █  █▄   ▄▀ █  █ "
    puts " █         ▀   █   █    ▄▀                     █    ▀███▀   ▀███▀       █      ▐ █  █ █ ███▀  ▀███▀     █  "
    puts "  ▀           █   ▀                             ▀                        ▀       █   ██                ▀   "
    puts "             ▀                                                                                             "
    puts
    puts "=" * 80
  end

  def success(message)
    puts "#{GREEN}#{message}#{RESET}"
  end

  def failure(message)
    puts "#{RED}#{message}#{RESET}"
  end

  def info(message)
    puts message
  end

  def progress_bar(current, total, width: 20, label: "specs")
    return if total.zero?

    # Clamp filled to width to handle when current > total
    filled = [(width * current / total.to_f).round, width].min
    empty = [width - filled, 0].max
    bar = '*' * filled + ' ' * empty
    spinner = SPINNER_FRAMES[@spinner_index % SPINNER_FRAMES.size]
    @spinner_index += 1

    # Show estimated total with ~ prefix
    print "\r[#{bar}] #{spinner} [#{current}/~#{total} #{label} tested]"
    $stdout.flush
  end

  def clear_progress
    print "\r" + " " * 80 + "\r"
    $stdout.flush
  end

  def parse_spec_input(input)
    path, line = input.split(':')
    [File.expand_path(path), line&.to_i]
  end

  def find_rails_root(spec_path)
    current_dir = File.dirname(spec_path)
    while current_dir != '/'
      return current_dir if File.exist?(File.join(current_dir, 'Gemfile'))
      current_dir = File.dirname(current_dir)
    end
    raise "Could not find Rails root from #{spec_path}"
  end

  def verify_target_spec_exists
    unless File.exist?(@spec_path)
      failure("✗ Spec file not found: #{@spec_path}")
      return false
    end

    unless @line_number
      failure("✗ Line number not provided")
      return false
    end

    true
  end

  def verify_spec_passes_in_isolation
    info("Step 1: Verifying spec passes in isolation...")
    result = run_spec(@spec_path_with_line)

    if result[:success]
      success("✓ Spec passes in isolation - good, now searching for polluting specs")
      true
    else
      failure("✗ Spec fails even in isolation - this is not a shared state issue")
      info("  The spec may have an inherent bug or environmental issue")
      false
    end
  end

  def spec_passes_with_same_file?
    info("\nStep 2: Testing with all specs in same file (except target)...")

    other_specs_in_file = get_all_spec_lines(@spec_path).reject { |line| line == @line_number }

    if other_specs_in_file.empty?
      info("No other specs in file, skipping to full suite search")
      return true
    end

    spec_args = other_specs_in_file.map { |line| "#{@spec_path}:#{line}" }
    spec_args << @spec_path_with_line

    result = run_spec(spec_args.join(' '))
    result[:success]
  end

  def find_problematic_file
    all_spec_files = get_all_spec_files.reject { |f| f == @spec_path }

    info("\nSearching through #{all_spec_files.size} spec files...")

    problematic_file = binary_search_files(all_spec_files)

    if problematic_file
      info("\n" + "=" * 80)
      success("Found problematic file: #{problematic_file}")
      info("=" * 80)
      info("\nNow searching within that file for the specific spec...")
      find_problematic_spec_in_file(problematic_file)
    else
      failure("\n✗ Could not identify a specific problematic file")
      info("  The flakiness may be caused by:")
      info("  - Multiple specs in combination")
      info("  - Test order within the target file")
      info("  - Environmental factors")
    end
  end

  def find_problematic_spec_in_file(file_path)
    spec_lines = get_all_spec_lines(file_path)

    if spec_lines.empty?
      failure("✗ No specs found in #{file_path}")
      return
    end

    info("\nSearching through #{spec_lines.size} specs in #{file_path}...")

    problematic_line = binary_search_specs(file_path, spec_lines)

    if problematic_line
      info("\n" + "=" * 80)
      success("FOUND PROBLEMATIC SPEC!")
      info("=" * 80)
      success("Conflicting spec: #{file_path}:#{problematic_line}")
      success("Target spec: #{@spec_path_with_line}")
      info("")
      show_spec_context(file_path, problematic_line)
      info("")
      show_llm_prompt(file_path, problematic_line)
      info("")
      info("To verify this conflict, run:")
      info("#{YELLOW}bundle exec rspec #{file_path}:#{problematic_line} #{@spec_path_with_line}#{RESET}")
    else
      failure("\n✗ Could not identify a specific problematic spec in this file")
    end
  end

  def binary_search_files(files)
    return nil if files.empty?
    return files.first if files.size == 1

    mid = files.size / 2
    left_half = files[0...mid]
    right_half = files[mid..]

    info("\nTesting left half (#{left_half.size} files)...")
    if test_with_files(left_half)
      failure("✗ Left half causes failure")
      binary_search_files(left_half)
    else
      success("✓ Left half passes, testing right half (#{right_half.size} files)...")
      if test_with_files(right_half)
        failure("✗ Right half causes failure")
        binary_search_files(right_half)
      else
        failure("✗ Neither half reproduces the failure")
        nil
      end
    end
  end

  def binary_search_specs(file_path, spec_lines)
    return nil if spec_lines.empty?
    return spec_lines.first if spec_lines.size == 1

    mid = spec_lines.size / 2
    left_half = spec_lines[0...mid]
    right_half = spec_lines[mid..]

    info("\nTesting left half (#{left_half.size} specs)...")
    if test_with_specs(file_path, left_half)
      failure("✗ Left half causes failure")
      binary_search_specs(file_path, left_half)
    else
      success("✓ Left half passes, testing right half (#{right_half.size} specs)...")
      if test_with_specs(file_path, right_half)
        failure("✗ Right half causes failure")
        binary_search_specs(file_path, right_half)
      else
        failure("✗ Neither half reproduces the failure")
        nil
      end
    end
  end

  def test_with_files(files)
    spec_args = files.join(' ') + ' ' + @spec_path_with_line
    total_files = files.size + 1
    result = run_spec(spec_args, show_progress: true, total_items: total_files, label: "files")
    !result[:success]
  end

  def test_with_specs(file_path, spec_lines)
    spec_args = spec_lines.map { |line| "#{file_path}:#{line}" }.join(' ')
    spec_args += ' ' + @spec_path_with_line
    total_specs = spec_lines.size + 1
    result = run_spec(spec_args, show_progress: true, total_items: total_specs, label: "specs")
    !result[:success]
  end

  def run_spec(spec_args, show_progress: false, total_items: nil, label: "items")
    Dir.chdir(@rails_root) do
      # Force TTY mode to get progress output
      command = if show_progress && total_items
                  "bundle exec rspec #{spec_args} --format progress --tty"
                else
                  "bundle exec rspec #{spec_args} --format progress"
                end

      if show_progress && total_items
        run_spec_with_progress(command, total_items, label)
      else
        info("  Running: #{command}")
        output = `#{command} 2>&1`
        success = $?.success?

        {
          success: success,
          output: output
        }
      end
    end
  end

  def run_spec_with_progress(command, total_items, label)
    require 'pty'

    output = String.new
    success = false
    item_count = 0
    last_update = Time.now
    buffer = String.new

    begin
      PTY.spawn(command) do |stdout, stdin, pid|
        stdin.close

        begin
          loop do
            # Update spinner periodically even if no new data
            if Time.now - last_update > 0.1
              progress_bar(item_count, total_items, label: label)
              last_update = Time.now
            end

            # Try to read with timeout
            if IO.select([stdout], nil, nil, 0.05)
              char = stdout.read_nonblock(1) rescue nil
              break if char.nil?

              output << char
              buffer << char

              # For file-based tracking, detect newlines after file paths
              # RSpec outputs like: "spec/path/to/file_spec.rb" followed by dots
              if label == "files" && char == "\n" && buffer =~ /_spec\.rb/
                item_count += 1
                progress_bar(item_count, total_items, label: label)
                last_update = Time.now
                buffer.clear
              # For spec-based tracking, count individual spec results
              elsif label == "specs" && (char == '.' || char == 'F' || char == '*' || char == 'E')
                item_count += 1
                progress_bar(item_count, total_items, label: label)
                last_update = Time.now
              end

              # Clear buffer periodically to prevent it from growing too large
              buffer.clear if buffer.size > 1000
            end
          end
        rescue Errno::EIO
          # End of output
        rescue IO::WaitReadable
          retry
        end

        Process.wait(pid)
        success = $?.success?
      end
    rescue PTY::ChildExited
      success = $?.success?
    end

    clear_progress

    {
      success: success,
      output: output
    }
  end

  def get_all_spec_files
    Dir.glob(File.join(@rails_root, 'spec', '**', '*_spec.rb')).sort
  end

  def get_all_spec_lines(file_path)
    spec_lines = []
    File.readlines(file_path).each_with_index do |line, idx|
      line_number = idx + 1
      if line.strip.start_with?('it ', 'specify ', 'example ', 'scenario ')
        spec_lines << line_number
      end
    end
    spec_lines
  end

  def show_spec_context(file_path, line_number)
    lines = File.readlines(file_path)
    start_line = [0, line_number - 6].max
    end_line = [lines.size - 1, line_number + 4].min

    info("Conflicting spec context:")
    info("-" * 80)
    (start_line..end_line).each do |i|
      prefix = i + 1 == line_number ? ">>> " : "    "
      info("#{prefix}#{i + 1}: #{lines[i]}")
    end
    info("-" * 80)
  end

  def show_llm_prompt(conflicting_file, conflicting_line)
    info("=" * 80)
    info("#{YELLOW}COPY-PASTE THIS PROMPT INTO CLAUDE:#{RESET}")
    info("=" * 80)
    puts <<~PROMPT

      I have a flaky RSpec test that passes in isolation but fails when run with another spec.

      **Target spec (the one that's flaky):**
      File: #{@spec_path}
      Line: #{@line_number}

      **Conflicting spec (causes the target to fail):**
      File: #{conflicting_file}
      Line: #{conflicting_line}

      Please analyze both specs and ultrathink:
      1. Identify what shared state is being polluted (database records, class variables, memoized values, global state, etc.)
      2. Explain exactly how the conflicting spec is affecting the target spec
      3. Provide a concrete plan to fix this, including:
         - Whether to fix the conflicting spec's cleanup
         - Whether to fix the target spec's setup/assumptions
         - Whether to add proper test isolation (database_cleaner, before hooks, etc.)
      4. Show the specific code changes needed

      Read both files to understand the full context.
    PROMPT
    info("=" * 80)
  end
end

if ARGV.empty?
  puts "Usage: #{File.basename(__FILE__)} SPEC_PATH:LINE_NUMBER"
  puts
  puts "Example: #{File.basename(__FILE__)} spec/requests/sellers_spec.rb:74"
  exit 1
end

FlakySpecFinder.new(ARGV[0]).call
