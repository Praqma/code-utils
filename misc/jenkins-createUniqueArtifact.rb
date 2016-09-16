#!/usr/bin/env ruby
# encoding: utf-8
require 'open3'
require 'docopt'
require 'yaml'
require "pp"
require 'fileutils'
require 'securerandom'

doc = <<DOCOPT

This script creates unique build artifacts that can be stored for later reference
and copied between jobs (copy artifact, archive artifact and fingerprinting).
It enables they can be saved as release artifacts, further it ensures that
build promotions have unique files to fingerprint and track dependency changes for.
This tracking means, if we copy these artifact along a pipeline, we can
track job dependency changes also.

Artifact are created as key=value pair for later re-use in other in other jobs or for reference.
The BUILD_ID serves as being unique, job-names and numbers make them easy to track.

To ensure uniqueness on Jenkins fingerprints using md5sum (based on only content), 
some files are added a UUID as a second line randomness.
If file content is not unique, Jenkins job tracebility will show wrong jobs as
changed in depedencies, for those with md5sum collisions.

Files are created in OUTDIR, if OUTDIR exists, use --force to delete it first.
Environment variables are required to be set - see below.

Created files - see below.
  
Usage:
  #{__FILE__} [-f] OUTDIR
  #{__FILE__} -h


Arguments:
  OUTDIR            destination path - must not exist and will be created

Options:
  -h --help         show this help message and exit
  -f --force        force deletion of existing output directory before creating files

Requires environment variables to exist
  * 'JOB_NAME' by Jenkins, not empty
  * 'BUILD_NUMBER' by Jenkins, not empty
  * 'BUILD_ID' by Jenkins

  * 'GIT_SHORT_SHA' preferably by Jenkins, else other scripts
  * 'GIT_COMMIT' preferably by Jenkins, else other scripts

  * 'PROJECT_BUILD_NUMBER'
  * 'PROJECT_VERSION_NUMBER'

Created files:

basename is: 'OUTDIR/${JOB_NAME}_${BUILD_NUMBER}-'

    * BUILD_ID.env
    * env-dump.out
    * GIT_COMMIT.env
    * GIT_SHORT_SHA.env
    * PROJECT_BUILD_NUMBER.env
    * PROJECT_VERSION_NUMBER.env
  
DOCOPT



# Write line into filename, and add UUID line
def write_file(filename, line)
  uuid = SecureRandom.uuid #=> "2d931510-d99f-494a-8c67-87feb05e1594"
  outline = line + $/ + "JENKINS_CREATE_UNIQUE_ARTIFACTS_RANDOM_STRING=" + uuid 
  # Create a new file and write to it  
  File.open(filename, 'w') do |f|  
    f.puts outline;  
  end  
end

begin
	if __FILE__ == $0
		params = Docopt::docopt(doc)
		#pp params
		
    out_dir = File.expand_path(params["OUTDIR"])
    if (File.exists?(out_dir) and (not params["--force"]))
      pp "ERROR - #{ __FILE__ }: Output directory #{ params["OUTDIR"] } exists. You need to delete it first, or give --force option."
    else
      FileUtils.rm_rf(out_dir) #, :verbose => true)
      FileUtils.mkdir_p(out_dir) #, :verbose => true)
    end
		
    if not ENV['JENKINS_SERVER_COOKIE']
      pp "WARNING - #{ __FILE__ }: It seems like you are not running on a Jenkins server - we expect typical environment variables from Jenkins to be available."
    end
    
    # gather all the environment variable we need, and check that the two used in filenames exists and are not empty
    env_vars = Hash.new()
    env_vars[:JOB_NAME]=""
    env_vars[:BUILD_NUMBER]=""
    env_vars.each do |k,v|
      if ENV["#{ k }"].nil? or ENV["#{ k }"].empty?
        abort("ERROR - #{ __FILE__ }: Environment variable '#{ k }' is not found or empty - must be set.")
      else
        env_vars[k] = ENV["#{ k}"]
      end
    end
    # these are used, but if empty or non-existing it is not a problem (UUID are added to the files)
    env_vars[:GIT_SHORT_SHA]=""
    env_vars[:GIT_COMMIT]=""
    env_vars[:BUILD_ID]=""
    env_vars[:PROJECT_BUILD_NUMBER]=""
    env_vars[:PROJECT_VERSION_NUMBER]=""
    env_vars.each do |k,v|
      if ENV["#{ k }"].nil? or ENV["#{ k }"].empty?
        env_vars[k] = ""
      else
        env_vars[k] = ENV["#{ k}"] 
      end
    end
    pp "#{ __FILE__ }: Running with following inputs:"
    pp params
    pp env_vars

  base_file_name=params["OUTDIR"] + "/" + env_vars[:JOB_NAME] + "_" + env_vars[:BUILD_NUMBER]
  
  # GIT_SHORT_SHA is planned to use to read along the pipeline in those cases where we can not transfer
  # the git sha with jenkins functionality.
  write_file(base_file_name + "-GIT_SHORT_SHA.env", "GIT_SHORT_SHA=" + env_vars[:GIT_SHORT_SHA])
    
  # GIT_COMMIT is the complete length version of GIT_SHORT_SHA
  write_file(base_file_name +  "-GIT_COMMIT.env", "GIT_COMMIT=" + env_vars[:GIT_COMMIT])
    
  # BUILD_ID
  #    The current build id, such as "2005-08-22_23-59-59" (YYYY-MM-DD_hh-mm-ss)
  write_file(base_file_name +  "-BUILD_ID.env", "BUILD_ID=" + env_vars[:BUILD_ID])
  
  # Both these build numbers are major.minor.path-buildnumber and will across project often hit the same version.
  write_file(base_file_name +  "-PROJECT_BUILD_NUMBER.env", "PROJECT_BUILD_NUMBER=" + env_vars[:PROJECT_BUILD_NUMBER])
  
  write_file(base_file_name +  "-PROJECT_VERSION_NUMBER.env", "PROJECT_VERSION_NUMBER=" + env_vars[:PROJECT_VERSION_NUMBER])

  # Puts all environment variables on key=value lines:
  envs = ENV
  env_lines = ""
  envs.each do |k,v|
    env_lines += "#{ k }=#{ v }" << $/
  end
  write_file(base_file_name +  "-env-dump.out", env_lines)

	end

rescue Docopt::Exit => e
	puts "ERROR - #{ __FILE__ } - wrong usage.\n" << e.message
	abort() # needed for non zero exit code
end
