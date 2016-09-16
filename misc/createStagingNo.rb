#!/usr/bin/ruby

# Parse input paramenter:
# one mandatory settings file in ruby (not validating the file)
if ARGV.length() != 1 then
  puts <<-EOF
Please provide a number for this script

usage:
  createStagingNo xxx

Will return a modulo 10 of the number as key=value pair to eg. set an ENV VAR
Can be used to do modulo on build number on jenkins jobs and use the number
as a round robin pointer to eg. deploy sub-directories.
EOF
  abort("Wrong input parameters")
else
  inputNo = ARGV[0];
end

begin
  puts  "PROJECT_STAGE_NO_FROM_BUILD=" + (Integer(inputNo) % 10).to_s()
rescue
  puts  "PROJECT_STAGE_NO_FROM_BUILD=x"
  abort("Could not convert input argument to number")
end
