# this is meant to be invoked via jenkins and assumes that jenkins has
# cloned/updated the source

# arguments, specified via "-D"
#   -DVERBOSITY=<0-5>
#   -DDASHSUBMIT=<TRUE|FALSE>    # mostly for debugging to avoid cdash submission
#   -DCDASHVER=<version of cdash>  # should be either 3.1 or not set

cmake_minimum_required(VERSION 3.23)

# verbosity level
#   0 - no specific screen output (default)
#   5 - all screen output available
if(NOT VERBOSITY)
  set(VERBOSITY 0)
endif()

# default TRUE
if(NOT DEFINED DASHSUBMIT)
  set(DASHSUBMIT TRUE)
endif()

# the version of cdash matters for the custom Test.xml file that is
# generated
if(NOT DEFINED CDASHVER)
  set(CDASHVER 0.0)
endif()

# error check
if(NOT DEFINED ENV{MYBUILDNAME})
  message(FATAL_ERROR "ERROR: Required environment varialble \"MYBUILDNAME\" not set")
endif()
if(NOT DEFINED ENV{branch})
  message(FATAL_ERROR "ERROR: Required environment varialble \"branch\" not set")
endif()
if(NOT DEFINED ENV{TESTSET})
  message(FATAL_ERROR "ERROR: Required environment variable \"TESTSET\" not set")
endif()

# function to list the contents of a specified subdirectory
#    dirname - full spec for directory to list
#    result - variable in parent into which the subdirectory name as
#             specified in the TAG file, will be set
function(GETTESTSUBDIR basedirname result)

  # read the TAG file to get the current test subdirectory name
  file(READ ${basedirname}/TAG tagFileContent)
  string(REGEX REPLACE "\n" ";" tagFileContent ${tagFileContent})

  list(GET tagFileContent 0 dirname)
  if(VERBOSITY GREATER 2)
    message("[VERB3]: directory name \"${dirname}\"")
  endif()

  # set the result in the caller. note that the value of result,
  # $result, is the name of the variable in the call
  set(${result} ${dirname} PARENT_SCOPE)
endfunction()

# function to read the custom xyce test results XML file and convert it
# to a format consistent with ctest for a unified submission. at
# present this just replaces the "BuildStamp" in the custom test
# results XML file with the one generated by ctest
#    inputfn - name of the custom xyce results file
#    subdirname - name of the subdirectory which ctest generated. this
#                 corresponds to the BuildStamp
#    track - the test track as used by ctest, one of Experimental,
#            Nightly, Weekly or Continuous
function(CONVERTTESTXML inputfn subdirname track)
  file(STRINGS ${inputfn} lines_list)
  foreach(fline ${lines_list})
    if(${fline} MATCHES "BuildStamp=\"(.*)\"")
      string(REGEX REPLACE "(.*BuildStamp=)\"(.*)\""  "\\1\"${subdirname}-${track}\"" outfline ${fline})
      list(APPEND new_line_list ${outfline})
    else()
      list(APPEND new_line_list ${fline})
    endif()
  endforeach()

  # convert the cmake list to a unified string with new lines
  string(REPLACE ";" "\n" out_contents "${new_line_list}")
  file(WRITE "$ENV{WORKSPACE}/build/Testing/${subdirname}/Test.xml" ${out_contents})
endfunction()

# macro to execute a Xyce executable with the "-capability" option in
# order to obtain a list of capabilities subsequently used when
# executign the run_xyce_regression script
function(GET_XYCE_CAPABILITIES xyce_exe)

  # execute Xyce with the "-capabilities" option
  execute_process(COMMAND ${xyce_exe} -capabilities
    RESULT_VARIABLE res_ret
    OUTPUT_VARIABLE term_cap_out
    ERROR_VARIABLE err_out)

  # if the execution fails
  if(NOT ${res_ret} EQUAL 0)
    message("ERROR: when querying Xyce capabilities. Error output:")
    message(FATAL_ERROR "${term_cap_out}")
  endif()

  # build up the tag list according to the output of the query. each
  # of the following is making a correspondence between a line output
  # by "Xyce -capabilities" and a tag to use when invoking
  # run_xyce_regression.
  set(TAGLIST "+serial?klu")
  if("$ENV{TESTSET}" STREQUAL "Weekly"
      OR "$ENV{TESTSET}" STREQUAL "QA"
      OR "$ENV{TESTSET}" STREQUAL "FINAL")

    set(TAGLIST "${TAGLIST}?weekly?nightly")
  else()
    set(TAGLIST "${TAGLIST}+nightly")
  endif()

  string(FIND "${term_cap_out}" "Verbose" res_var)
  if(${res_var} EQUAL -1)
    set(TAGLIST "${TAGLIST}-verbose?noverbose")
  else()
    set(TAGLIST "${TAGLIST}?verbose-noverbose")
  endif()

  string(FIND "${term_cap_out}" "Non-Free device models" res_var)
  if(NOT ${res_var} EQUAL -1)
    set(TAGLIST "${TAGLIST}?nonfree")
  endif()

  string(FIND "${term_cap_out}" "Radiation models" res_var)
  if(NOT ${res_var} EQUAL -1)
    set(TAGLIST "${TAGLIST}?rad")
    string(FIND "${term_cap_out}" "Reaction parser" res_var)
    if(NOT ${res_var} EQUAL -1)
      set(TAGLIST "${TAGLIST}?qaspr")
    endif()
  endif()

  string(FIND "${term_cap_out}" "ATHENA" res_var)
  if(NOT ${res_var} EQUAL -1)
    set(TAGLIST "${TAGLIST}?athena")
  endif()

  string(FIND "${term_cap_out}" "FFT" res_var)
  if(NOT ${res_var} EQUAL -1)
    set(TAGLIST "${TAGLIST}?fft")
  endif()

  string(FIND "${term_cap_out}" "C++14" res_var)
  if(NOT ${res_var} EQUAL -1)
    set(TAGLIST "${TAGLIST}?cxx14")
  endif()

  string(FIND "${term_cap_out}" "Stokhos enabled" res_var)
  if(NOT ${res_var} EQUAL -1)
    set(TAGLIST "${TAGLIST}?stokhos")
  endif()

  string(FIND "${term_cap_out}" "ROL enabled" res_var)
  if(NOT ${res_var} EQUAL -1)
    set(TAGLIST "${TAGLIST}?rol")
  endif()

  string(REGEX MATCH "Amesos2.*Basker.*enabled" out_var "${term_cap_out}")
  if(out_var)
    set(TAGLIST "${TAGLIST}?amesos2basker")
  endif()

  string(REGEX MATCH "Amesos2.*KLU2.*enabled" out_var "${term_cap_out}")
  if(out_var)
    set(TAGLIST "${TAGLIST}?amesos2klu")
  endif()

  find_program(XDMBDLEXE NAMES xdm_bdl)
  if(NOT ${XDMBDLEXE} STREQUAL "XDMBDLEXE-NOTFOUND")
    set(TAGLIST "${TAGLIST}?xdm")
  endif()

  if(VERBOSITY GREATER 1)
    message("[VERB2]: TAGLIST=\"${TAGLIST}\"")
  endif()

endfunction()

# WORKSPACE is an environment variable set by jenkins
set(CTEST_SOURCE_DIRECTORY "$ENV{WORKSPACE}/source/Xyce")

# the specified directory must exist or ctest will error out
set(CTEST_BINARY_DIRECTORY "$ENV{WORKSPACE}/build")

# this should probably be a variable in the environment or passed in,
# but for now it's hard-coded to 1am
set(CTEST_NIGHTLY_START_TIME "01:00:00 MDT")

# use the "hostname" command as the CTEST_SITE variable, which is used
# in the "Site" column on the dashboard
find_program(HNAME NAMES hostname)
execute_process(COMMAND "${HNAME}"
  OUTPUT_VARIABLE CTEST_SITE
  OUTPUT_STRIP_TRAILING_WHITESPACE)

# find the custom xyce regression testing script
find_program(XYCE_REGR_SCRIPT run_xyce_regression
  HINTS $ENV{WORKSPACE}/tests/Xyce_Regression/TestScripts
  REQUIRED)

# find the custom perl script to create the results XML file. note
# that different versions of cdash can require slight different
# formats for the XML files.
if(${CDASHVER} EQUAL 3.1)
  find_program(XYCE_CDASH_GEN summary-dart-nosubmit.cdash-v3p1.pl
    HINTS $ENV{WORKSPACE}/Scripts/reporting
    REQUIRED)
else()
  find_program(XYCE_CDASH_GEN summary-dart-nosubmit.pl
    HINTS $ENV{WORKSPACE}/Scripts/reporting
    REQUIRED)
endif()

# this is used as the "Build Name" column on the dashboard
set(CTEST_BUILD_NAME "$ENV{MYBUILDNAME}")

# used for invocation of parallel make
if(DEFINED ENV{NUM_JOBS})
  set(CTEST_BUILD_FLAGS "-j$ENV{NUM_JOBS}")
else()
  set(CTEST_BUILD_FLAGS "-j8")
endif()

set(CTEST_CMAKE_GENERATOR "Unix Makefiles")

# note that "Weekly" is just a Nightly category with a different group
# name
if(NOT DEFINED ENV{TESTSET})
  message(FATAL_ERROR "ERROR: You must set the environment variable TESTSET to one of Nighlty, Weekly or Experimental")
endif()

if($ENV{TESTSET} STREQUAL "Nightly")
  set(MODEL "Nightly")
  set(TESTGROUP "Nightly")
elseif($ENV{TESTSET} STREQUAL "Weekly")
  set(MODEL "Nightly")
  set(TESTGROUP "Weekly")
else()
  set(MODEL "Experimental")
  set(TESTGROUP "Experimental")
endif()

set(CTEST_PROJECT_NAME "Xyce")

set(CTEST_DROP_METHOD "https")
set(CTEST_DROP_SITE "xyce-cdash.sandia.gov")
set(CTEST_DROP_LOCATION "/submit.php?project=Xyce")

# begin ctest procedures. MODEL should be one of Nighlty, Weekly,
# Continuous or Experimental. this can use custom categories via the
# GROUP option to ctest_start() if desired
ctest_start(${MODEL} GROUP ${TESTGROUP})

# this runs cmake on xyce
ctest_configure()

# this runs make
ctest_build()

# generate the taglist for the regression testing scripg
GET_XYCE_CAPABILITIES(${CTEST_BINARY_DIRECTORY}/src/Xyce)

# run the custom xyce regression test script
message("executing custom xyce regression test script, ${XYCE_REGR_SCRIPT}...")
execute_process(COMMAND ${XYCE_REGR_SCRIPT}
  --output=$ENV{WORKSPACE}/build/Xyce_Regression
  --xyce_test=$ENV{WORKSPACE}/tests/Xyce_Regression
  --xyce_verify=$ENV{WORKSPACE}/tests/Xyce_Regression/TestScripts/xyce_verify.pl
  --ignoreparsewarnings
  --taglist=${TAGLIST}
  --resultfile=$ENV{WORKSPACE}/build/regr_test_results_all
  $ENV{WORKSPACE}/build/src/Xyce
  OUTPUT_VARIABLE regrOut
  ERROR_VARIABLE regrOut
  RESULT_VARIABLE xyce_reg_result)

if(VERBOSITY GREATER 3)
  message("[VERB4]: exit status of regression script ${XYCE_REGR_SCRIPT}: ${xyce_reg_result}")
  message("[VERB4]: screen output from regression script ${XYCE_REGR_SCRIPT}: ${regrOut}")
endif()

# run the perl script to summarize results for submission to the dashboard
if(VERBOSITY GREATER 1)
  message("[VERB2]: XYCE_CDASH_GEN = ${XYCE_CDASH_GEN}")
  message("[VERB2]:   CTEST_SITE = ${CTEST_SITE}")
  message("[VERB2]:   MYBUILDNAME = $ENV{MYBUILDNAME}")
  message("[VERB2]:   branch = $ENV{branch}")
  message("[VERB2]:   output file name = $ENV{WORKSPACE}/build/regr_test_results_all")
  message("[VERB2]:   TESTSET = $ENV{TESTSET}")
endif()

message("executing custom xyce regression report script, ${XYCE_CDASH_GEN}")
execute_process(COMMAND ${XYCE_CDASH_GEN}
  ${CTEST_SITE}
  $ENV{MYBUILDNAME}
  $ENV{branch}
  $ENV{WORKSPACE}/build/regr_test_results_all
  $ENV{TESTSET}
  OUTPUT_VARIABLE submitOut
  ERROR_VARIABLE submitOut
  RESULT_VARIABLE xyce_cdash_gen_result)
if(VERBOSITY GREATER 3)
  message("[VERB4]: exit status of script ${XYCE_CDASH_GEN}: ${xyce_cdash_gen_result}")
  message("[VERB4]: screen output from script ${XYCE_CDASH_GEN}: ${submitOut}")
endif()

# figure out the directory for the dashboard submission and copy the
# custom results file into it
GETTESTSUBDIR($ENV{WORKSPACE}/build/Testing testSubDirName)
if(VERBOSITY GREATER 4)
  message("[VERB5]: Active \"Testing\" subdirectory name: ${testSubDirName}")
endif()
if(VERBOSITY GREATER 4)
  message("[VERB5]: Using \"${testSubDirName}\" for test results")
endif()

# this will convert the "BuildStamp" generated and written to the XML
# file by the custom xyce perl script to the same generated by
# ctest. this will make the configure, build, and test results show up
# on the same line in cdash.
CONVERTTESTXML($ENV{WORKSPACE}/build/regr_test_results_all.xml
  ${testSubDirName}
  $ENV{TESTSET})

# submit results to the dashboard
if(DASHSUBMIT)
  ctest_submit(RETRY_COUNT 10 RETRY_DELAY 30)
endif()
