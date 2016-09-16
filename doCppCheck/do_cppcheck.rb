#!/usr/bin/ruby

# This program run the static analysis tool Cppcheck.
# It takes a configuration file (also in Ruby) as mandatory parameter.
#
# Call as shown in usage below, or just try executing it without parameters.
#
# NOtES about design:
# - if cppcheck offers a solution, eg. excluding or including files, it is used (eg. using suppression list parameter over cleaning the output afterwards with the script)
# - every confiuration, both cppcheck parameters, exclude files etc., is defined in a file under revision control
# - it supposed not to clean up it temporary files, as these might be need later for further debugging
# - the out-file name is hardcoded by choice, to avoid developers changing it easily and therefore
# requiring automated build configuration changes. We will avoid this as it makes it more difficult to 
# automatically build old revision without changing build job defintions.


require "find"
require "fileutils"
require "open3"

# Parse input paramenter:
# one mandatory settings file in ruby (not validating the file)
if ARGV.length() != 1 then
	puts <<-EOF
Please provide a settings file as only parameter

Usage:
	do_cppcheck.rb cppcheck_settings.rb
EOF
	abort("Wrong input parameters")
else 
	# assume file is in correct format and load it
	puts "Using settingsfile: " + ARGV[0]
	load ARGV[0]
end


# Cross-platform way of finding an executable in the $PATH.
#
#   which('ruby') #=> /usr/bin/ruby
def which(cmd)
  exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
  ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
    exts.each { |ext|
      exe = "#{path}/#{cmd}#{ext}"
      return exe if File.executable? exe
    }
  end
  return nil
end


# Searches each directory in the dirlist recursively for file basenames
# matching string or regular expression name.
# For example find all .cpp files with the regexp like:
# /^[a-zA-Z0-9_]+.cpp$/
# Note the dolar sign in the end for looking for suffixes
# Params:
# +dirlist+:: list of directories (current directory is accepted)
# +name+:: a string or regexp to match against the file basename
# Returns:
# +list+:: a list of files with path relative to the searched directory
def find_files(dirlist, name, suffix)
	list = []
	dirlist.each{|dir|
	Find.find(dir) do |path|
		case name
			when String
				list << path if File.basename(path) == name
			when Regexp
				list << path if File.basename(path) =~ name
		else
			raise ArgumentError
		end
	end
	}
	if suffix.length() == 0 then
		return list
	else
		list_suffix_filtered = [ ] 
		suffix.each{|suffix|
			case suffix
				when String
					list_suffix_filtered.concat( list.select { |file| File.extname(file).eql?(suffix) } )
				when Regexp
					list_suffix_filtered.concat( list.select { |file| suffix.match(File.extname(file)) } )
				else
					raise ArgumentError
			end
		}
	return list_suffix_filtered
	end
end

# Filters a list of strings from a blacklist strings or regexps.
# Params:
# +inlist+:: list of strings (supposely file names)
# +blacklist+:: list of strings or regexp used to filter out matches in the inlist
def filter_list(inlist, blacklist)
	blacklist.each{|bitem|	
		case bitem
			when String
				inlist.delete_if { |item| item.include?(bitem) }
			when Regexp
				inlist.delete_if { |item| bitem.match(item) }
		else
			raise ArgumentError
		end
	}
end

# is the string in the list a file?
def sanitize_filelist(listOfFiles)
	listOfFiles.each{|fileString|
		listOfFiles.delete_if { |fileString| !File.file?(fileString) }
	}	
end

def backup_existing_file(filename)
	# Safety check - will not overwrite existing file - renames old
	if File.exists?(filename) then
		FileUtils.cp(filename, filename + ".bak")
		puts "Filename '" + filename + "' to write already exist - saved old with '.bak' suffix"
	end
end


def write_filelist(listOfFiles, filename, sanitize=false)
	if sanitize then
		sanitize_filelist(listOfFiles)
	end
	# Safety check - will not overwrite existing file - renames old
	backup_existing_file(filename)

	File.open(filename, 'w') do |f|
		listOfFiles.each{|file|
				f << file << "\n"
		}
	end
end

def extract_unique_dir(listOfFiles)
	listOfFiles.map! { |file| File.dirname(file) }
	listOfFiles.uniq!
end


def run_command(command, failIfstdError=false)
	# FIXME We should upgrade to Ruby 1.9.3 soon, to be able to user newer version
	# of Open3, that can check exit status and other nice stuff.
	puts "\n\n\n================================================================================"
	puts "Running Cppcheck command now: " + command
	stdin, stdout, stderr = Open3.popen3(command)
	result = 0 # to be used later when Open3 can return this
	output = stdout.read
	errors = stderr.read
	puts "================================================================================"
	puts "Output (stdout) was:"
	puts output
	if !(errors.empty?) then
		puts "================================================================================"
		puts "There is errors, stderr) not empty:"
		puts errors
		if failIfstdError then
			abort("Command returned messages to stderr, asuming errors and failing")
		end
	end
	return output, errors, result, command
end


source_files = find_files(CppcheckSettings::SRC_SEARCH_PATH, CppcheckSettings::SRC_FILE_SEARCH_REGEXP, CppcheckSettings::SRC_SUFFIX_LIST)
filter_list(source_files, CppcheckSettings::SRC_BLACKLIST_PATTERNS)
write_filelist(source_files, "cppcheckSourceFiles.lst", true)

header_files = find_files(CppcheckSettings::HEADER_SEARCH_PATH, CppcheckSettings::HEADER_FILE_SEARCH_REGEXP, CppcheckSettings::HEADER_SUFFIX_LIST)
filter_list(header_files, CppcheckSettings::HEADER_BLACKLIST_PATTERNS)

extract_unique_dir(header_files)
header_files.concat CppcheckSettings::HEADER_APPEND_DIR_LIST
write_filelist(header_files, "cppcheckHeaderFiles.lst")

puts which('cppcheck')

# It is my intention to hard-code the cppcheck result xm-file, and NOT letting 
# the user decide the name. We will use that specific file in the Jenkins CI 
# server job configuration, thus is "someone" decides to  change it, job
# configuration need to be changes as well.
# - this is a problem as it can go unotised if old file exist
# - it also give problems if one like to make historical build and not
# changing the job configuration
cppcheckResultFile = "cppcheck-results.xml"

# Check if using suppression list for cppcheck warnings and prepare the list for cppcheck
# We will like comments in the file, but cppcheck can not handle that, so we remove them
suppressions_list_parameter = ""
if (defined? CppcheckSettings::CPPCHECK_SUPPRESSION_FILE) then
	suppressions_list_parameter = "--suppressions-list=" + CppcheckSettings::CPPCHECK_SUPPRESSION_FILE
end

cppcheck_common_params = " " + CppcheckSettings::CPPCHECK_ADDITIONAL_PARAMETERS.map! { |p| p}.join(" ") + " " + suppressions_list_parameter + " --file-list=cppcheckSourceFiles.lst" + " --includes-file=cppcheckHeaderFiles.lst"

# To support threads, job numbers, of cppcheck, we check an environment variable and if set we use that numbers of jobs parameter to cppcheck
if ENV['CPPCHECK_THREAD_COUNT'] then
  jobs_parameter = "-j " + ENV['CPPCHECK_THREAD_COUNT']
  puts "do_cppcheck script found env. var. CPPCHECK_THREAD_COUNT so using job parameter: " + jobs_parameter
  cppcheck_common_params = " " + jobs_parameter + " " + cppcheck_common_params
end

run_command(CppcheckSettings::CPPCHECK_EXEC + " --version")
run_command(CppcheckSettings::CPPCHECK_EXEC + " --check-config" + cppcheck_common_params, CppcheckSettings::FAIL_ON_STDERR_MSG)
backup_existing_file(cppcheckResultFile)
run_command(CppcheckSettings::CPPCHECK_EXEC + " --enable=all"  + cppcheck_common_params + " --xml 2> " + cppcheckResultFile, CppcheckSettings::FAIL_ON_STDERR_MSG)


if CppcheckSettings::FAIL_ON_MISSING_HEADER_FILES then
	missing_includes = [ ]
	File.open( 'cppcheck-results.xml' ).each do |line|
		if line =~ /.+Cppcheck cannot find all the include files.*/ then
			puts "cppcheck found errors that is so important that we must fail!: \n" + line + "\n\n" + missing_includes.map! { |l| l}.join("")
			# okay here, because cppcheck add this line last!
			abort("Cppcheck found errors that means we did not analyse everything - fix it checking the results in cppcheck-results.xml")
		elsif line =~ /.+id="missingInclude".*/ then
			missing_includes << line
		end
	
	end
end
