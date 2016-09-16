#!/usr/bin/ruby

module CppcheckSettings

#############################
# do_cppcheck configuration #
#############################
# Should this script fail with an error if cppcheck reports it can not
# find every header file during analysis?
# This mean the scripts abort if the following error is found in the results:
# "error id="missingInclude" severity="style" msg="Cppcheck cannot find all the include files (use --check-config for details)"
FAIL_ON_MISSING_HEADER_FILES = true
# fail script if errors from commands are reported?
FAIL_ON_STDERR_MSG = true

###############################################################################
# Sources
###############################################################################
### Searching for source files configuration ###
# Search recursively from this lists of paths (regexp or string).
# Current path . (period) is allowed.
SRC_SEARCH_PATH = [ "." ]
# Find file matching this regexp:
SRC_FILE_SEARCH_REGEXP = /^[a-zA-Z0-9_]+.cpp/ # might also use /^[a-zA-Z0-9_]+.cpp$/

### Filtering sources and excluding sources ###
# Whitelist of filename suffixes - regexp or string
# MUST include the . (period)
# This list can be empty, if SRC_FILE_SEARCH_REGEXP only find exactly those file
# with correct ending.
SRC_SUFFIX_LIST = [ /\.cpp$/ ]

# Exclude all files and directories containing one of these string
# or matching one the regexp.
SRC_BLACKLIST_PATTERNS = [ /\.\/include\/msg_bus*/, "host", "vendor", "docs", "examples", "test", "tools", /\/moc_*/, /Adaptor.cpp$/, /Proxy.cpp$/ ]

###############################################################################
# Headers - settings follows same conventions as the sources above
###############################################################################
HEADER_SEARCH_PATH = [ "." ]
HEADER_FILE_SEARCH_REGEXP = /^[a-zA-Z0-9_]+.\.h$/
HEADER_SUFFIX_LIST = [ ]

HEADER_BLACKLIST_PATTERNS = [ /\.\/host\//, /\.\/docs\//, /\.\/examples\//, /\.\/tools\//, /\.\/test\//  ]

# Append these headers manually to Cppcheck. Eg. if they can not be found automatically.
# The will be given to cppcheck with the prefix -I (for include dirs)
HEADER_APPEND_DIR_LIST = [ "./msgbus_applications/view/include", "/usr/include/qt4/QtCore" ]


##########################
# Cppcheck configuration #
##########################
# Cppcheck executeable name
CPPCHECK_EXEC="cppcheck"

# Currently we execute cppcheck this way, first with --check-config then with --enable=all for the real analysis
# cppcheck --enable=all" + " --file-list=cppcheckSourceFiles.lst" + " --includes-file=cppcheckHeaderFiles.lst"
# The real check also have " --xml 2> cppcheck-results.xml" added for output to a file.
# To check possible parameters, run cppcheck --help.
# For example you could add -DQT_DEPRECATED -DQT3_SUPPORT to avoid checking those configurations.
CPPCHECK_ADDITIONAL_PARAMETERS = [ "-DQT3_support", "-DQT_DEPRECATED" ]

# Note on threads: do_cppcheck.rb script will automatically look for env. var. CPPCHECK_THREAD_COUNT and use that
# as -j $CPPCHECK_THREAD_COUNT for using more jobs in parallel when checking. It is not part of the additional
# parameter above, as optimal thread count will differ from build host to build host, thus it better selecting it
# automatically.

# Reference to file with errors to whitelist
# Read the file for how to suppress warnings from Cppcheck.
# It it does not exist, a template should be available with the script
# Comment out if not used!
CPPCHECK_SUPPRESSION_FILE = "do_cppcheck-suppressions.lst"

end
