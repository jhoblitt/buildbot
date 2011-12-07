#! /bin/bash
# install a requested package from version control, and recursively
# ensure that its minimal dependencies are installed likewise

LSST_STACK=/lsst/DC3/stacks/gcc445-RH6/28nov2011

# URL pointing to the log files; used in emailed report
# URL_BUILDERS="http://dev.lsstcorp.org/build/builders"
# URL_BUILDERS="http://lsst-build.ncsa.illinois.edu:8010/builders"
URL_BUILDERS="http://lsst-build4.ncsa.illinois.edu:8020/builders"

#--------------------------------------------------------------------------
usage() {
#80 cols  ................................................................................
    echo "Usage: $0 [options] package"
    echo "Install a requested package from version control (trunk), and recursively"
    echo "ensure that its dependencies are also installed from version control."
    echo
    echo "Options:"
    echo "                -verbose: print out extra debugging info"
    echo "                  -force: if package already installed, re-install "
    echo "       -dont_log_success: if specified, only save logs if install fails"
    echo "        -log_dest <dest>: scp destination for config.log,"
    echo "                          eg \"buildbot@master:/var/www/html/logs\""
    echo "          -log_url <url>: URL prefix for the log destination,"
    echo "                          eg \"http://master/logs/\""
    echo "    -builddir <instance>: identifies slave instance at \"slave/<name>\""
    echo "  -build_number <number>: buildbot's build number assigned to run"
    echo "    -slave_devel <path> : LSST_DEVEL=<path>"
    echo "             -production: setting up stack for production run"
    echo "               -no_tests: only build package, don't run tests"
    echo "       -parallel <count>: if set, parallel builds set to <count>"
    echo "                          else, parallel builds count set to 2."
    echo " where $PWD is location of slave's work directory"
}
#--------------------------------------------------------------------------

DEBUG=debug
DEV_SERVER="lsstdev.ncsa.uiuc.edu"
SCM_SERVER="git.lsstcorp.org"
WEB_ROOT="/var/www/html/doxygen"

source ${0%/*}/gitBuildFunctions.sh

#Exclude known persistent test failures until they are fixed or removed
#   Code Developer should install into tests/SConscript:
#       ignoreList=["testSdqaRatingFormatter.py"]
#       tests = lsst.tests.Control(env, ignoreList=ignoreList, verbose=True)
# If not use e.g.    SKIP_THESE_TESTS="| grep -v testSdqaRatingFormatter.py "
SKIP_THESE_TESTS=""


#--------------------------------------------------------------------------
# ---------------
# -- Functions --
# ---------------
#--------------------------------------------------------------------------
# -- Some LSST internal packages should never be built from trunk --
# $1 = eups package name
# return 0 if a special LSST package which should be considered external
# return 1 if package should be processed as usual
package_is_special() {
    if [ "$1" = "" ]; then
        print_error "No package name provided for package_is_special check. See LSST buildbot developer."
        exit 1
    fi
    local SPCL_PACKAGE="$1"

    # 23 Nov 2011 installed toolchain since it's not in active.list, 
    #             required by tcltk but not an lsstpkg distrib package.
    if [ ${SPCL_PACKAGE:0:5} = "scons" \
        -o ${SPCL_PACKAGE} = "toolchain"  \
        -o ${SPCL_PACKAGE:0:7} = "devenv_"  \
        -o $SPCL_PACKAGE = "gcc"  \
        -o $SPCL_PACKAGE = "afwdata" \
        -o $SPCL_PACKAGE = "astrometry_net_data" \
        -o $SPCL_PACKAGE = "isrdata"  \
        -o $SPCL_PACKAGE = "meas_multifitData"  \
        -o $SPCL_PACKAGE = "auton"  \
        -o $SPCL_PACKAGE = "ssd"  \
        -o $SPCL_PACKAGE = "mpfr"  \
        -o ${SPCL_PACKAGE:0:6} = "condor"  \
        -o $SPCL_PACKAGE = "base"  \
        -o ${SPCL_PACKAGE:0:5} = "mops_"  \
        -o ${SPCL_PACKAGE:0:4} = "lsst" ]; then 
        return 0
    else
        return 1
    fi
}

#--------------------------------------------------------------------------
# -- On Failure, email appropriate notice to proper recipient(s)
# $1 = package
# $2 = version
# $3 = recipients  (May have embedded blanks)
#      Note BLAME details are fetched at point of failure and ready for use
#           FAIL_MSG is also set prior to invocation
# return: 0  

emailFailure() {
    local emailPackage=$1; shift
    local emailVersion=$2; shift
    local emailRecipients=$*;

    if [ "$BLAME_EMAIL" != "" ] ; then
        MAIL_TO="$emailRecipients, $BLAME_EMAIL"
    else
        MAIL_TO="$emailRecipients"
    fi
    URL_MASTER_BUILD="$URL_BUILDERS/$BUILDER_NAME/builds"
    EMAIL_SUBJECT="LSST automated build failure: package $emailPackage in $BUILDER_NAME"

    [[ "$DEBUG" ]] && print "TO: $MAIL_TO; Subject: $EMAIL_SUBJECT; $BUILDER_NAME"

    rm -f email_body.txt
    printf "\
from: \"Buildbot\" <$BUCK_STOPS_HERE>\n\
subject: $EMAIL_SUBJECT\n\
to: \"Godzilla\" <robyn@noao.edu>\n\
cc: \"Mothra\" <$BUCK_STOPS_HERE>\n" \
>> email_body.txt
#to: \"Godzilla\" <robyn@lsst.org>\n" \
# REPLACE 'TO:' ABOVE " to: $MAIL_TO\n"               & add trailing slash
# Also  add           " cc: $BUCK_STOPS_HERE\n\n "    & add trailing slash

    # Following is if error is failure in Compilation/Test/Build
    if  [ "$BLAME_EMAIL" != "" ] ; then
        printf "\
$FAIL_MSG\n\n\
You were notified because you are either the package's owner or its last modifier.\n\n\
The $PACKAGE failure log is available at: ${URL_MASTER_BUILD}/${BUILD_NUMBER}/steps/$PACKAGE/logs/stdio\n\
The Continuous Integration build log is available at: ${URL_MASTER_BUILD}/${BUILD_NUMBER}\n \
Change info:\n" \
>> email_body.txt
        cat $BLAME_TMPFILE \
>> email_body.txt
    else  # For Non-Compilation/Test/Build failures directed to BUCK_STOPS_HERE
        printf "\
An build/installation of package \"$emailPackage\" (version: \"$emailVersion\") failed\n\n\
You were notified because you are Buildbot's nanny.\n\n\
$FAIL_MSG\n\n\
The $PACKAGE failure log is available at: ${URL_MASTER_BUILD}/${BUILD_NUMBER}/steps/$PACKAGE/logs/stdio\n"\
>> email_body.txt
    fi

    printf "\
\n--------------------------------------------------\n\
Sent by LSST buildbot running on `hostname -f`\n\
Questions?  Contact $BUCK_STOPS_HERE \n" \
>> email_body.txt

    /usr/sbin/sendmail -t < email_body.txt
    rm email_body.txt
###_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_
## Uncomment the next command  when ready to send to developers
###_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_
#    #cat email_body.txt | mail -c "$BUCK_STOPS_HERE" -s "$EMAIL_SUBJECT" "$EMAIL_RECIPIENT"
}

###_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_
#                 Might want to reuse following to avoid duplicate emails
###_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_
#emailFailure() {
#    if [ "$3" = "FETCH_BLAME" ]; then
#        # Determine last developer to modify the package
#        local LAST_MODIFIER=`svn info $SCM_LOCAL_DIR | grep 'Last Changed Author: ' | sed -e "s/Last Changed Author: //"`
#    
#        # Is LAST_MODIFIER already in the list of PACKAGE_OWNERS (aka $emailVersion)?
#        local OVERLAP=`echo ${2}  | sed -e "s/.*${LAST_MODIFIER}.*/FOUND/"`
#        unset DEVELOPER
#        if [ "$OVERLAP" != "FOUND" ]; then
#            local url="$PACKAGE_OWNERS_URL?format=txt"
#            DEVELOPER=`curl -s $url | grep "sv ${LAST_MODIFIER}" | sed -e "s/sv ${LAST_MODIFIER}://" -e "s/ from /@/g"`
#            if [ ! "$DEVELOPER" ]; then
#                DEVELOPER=$BUCK_STOPS_HERE
#                print "*** Error: did not find last modifying developer of ${LAST_MODIFIER} in $url"
#                print "*** Expected \"sv <user>: <name> from <somewhere.dom>\""
#            fi
#    
#            print "$BUCK_STOPS_HERE will send build failure notification to $2 and $DEVELOPER"
#            MAIL_TO="$2, $DEVELOPER"
#        else
#            print "$BUCK_STOPS_HERE will send build failure notification to $2"
#        fi
#    fi
###_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_
#--------------------------------------------------------------------------

# -------------------
# -- get arguments --
# -------------------

options=$(getopt -l verbose,boot,force,dont_log_success,log_dest:,log_url:,builder_name:,build_number:,slave_devel:,production,no_tests,parallel:,package: -- "$@")

LOG_SUCCESS=0
BUILDER_NAME=""
BUILD_NUMBER=0
PRODUCTION_RUN=1
DO_TESTS=0
SLAVE_DEVEL="xyzzy"
while true
do
    case $1 in
        --verbose) VERBOSE=true; shift;;
        --debug) VERBOSE=true; shift;;
        --force) FORCE=true; shift;;
        --dont_log_success) LOG_SUCCESS=1; shift;;
        --log_dest) 
                LOG_DEST=$2; 
                LOG_DEST_HOST=${LOG_DEST%%\:*}; # buildbot@master
                LOG_DEST_DIR=${LOG_DEST##*\:};  # /var/www/html/logs
                shift 2;;
        --log_url) LOG_URL=$2; shift 2;;
        --builder_name)
                BUILDER_NAME=$2; 
                print "BUILDER_NAME: $BUILDER_NAME"
                shift 2;;
        --build_number)
                BUILD_NUMBER=$2;
                print "BUILD_NUMBER: $BUILD_NUMBER"
                shift 2;;
        --slave_devel) SLAVE_DEVEL=$2; shift 2;;
        --production) PRODUCTION_RUN=0; shift 1;;
        --no_tests) DO_TESTS=1; shift 1;;
        --parallel) PARALLEL=$2; shift 2;;
        --package) PACKAGE=$2; shift 2;;
        *) echo "parsed options; arguments left are: $*"
             break;;
    esac
done

echo "SLAVE_DEVEL = $SLAVE_DEVEL"
if [ "$SLAVE_DEVEL" = "xyzzy" ]; then
    echo "Missing argument --slave_devel must be specified"
    exit 1
fi

if [ ! -d $LSST_DEVEL ] ; then
    print_error "LSST_DEVEL: $LSST_DEVEL does not exist; contact the LSST buildbot guru."
    exit 1
fi

PACKAGE=$1
if [ "$PACKAGE" = "" ]; then
    echo  "No package name was provided as an input parameter; contact the LSST buildbot guru."
    exit 1
fi

print "PACKAGE: $PACKAGE"

WORK_PWD=`pwd`

#Allow developers to access slave directory
umask 002

source $LSST_STACK"/loadLSST.sh"

#*************************************************************************
#First action...rebuild the $LSST_DEVEL cache
pretty_execute "eups admin clearCache -Z $LSST_DEVEL"
pretty_execute "eups admin buildCache -Z $LSST_DEVEL"



print_error "Testing, Testing, Testing that print_error() output is Red."

#*************************************************************************
step "Determine if $PACKAGE will be tested"

package_is_special $PACKAGE
if [ $? = 0 ]; then
    print "Selected packages are not tested via trunk-vs-trunk, $PACKAGE is one of them"
    exit 0
fi
package_is_external $PACKAGE
if [ $? = 0 ]; then 
    print "External packages are not tested via trunk-vs-trunk"
    exit 0
fi


prepareSCMDirectory $PACKAGE "BOOTSTRAP"
if [ $RETVAL != 0 ]; then
    print_error="Failed to extract source directory for $PACKAGE."
    exit 1
fi
PACKAGE_SCM_REVISION=$RET_REVISION
[[ "$DEBUG" ]] && print "PACKAGE: $PACKAGE PACKAGE_SCM_REVISION: $PACKAGE_SCM_REVISION"

#***********************************************************************
# In order to get an accurate dependency table, ALL master SCM directories
# must be extracted and 'setup -j <name>'  so that eups can deduce
# the dependencies from the source tree.  Only then should the build
# of the dependencies commence in the order specified.
#***********************************************************************

# -- setup root package in prep for dependency list generation
# -- First, setup all dependencies for default system version of <package>
# -- Second, re-setup only trunk of <package>, leaving dependencies as before
# --   This sets stage for ordering dependencies based on setup versions  
pretty_execute "setup --tag stable $PACKAGE"
[[ $RETVAL != 0 ]] && print "Warning: unable to eups-setup the stable versions of dependent packages; perhaps $PACKAGE not yet LSST-Released."

cd $SCM_LOCAL_DIR
pretty_execute "setup -r . -j "
if [ $RETVAL != 0 ]; then
    print_error "FAILURE to eups-setup the 'LOCAL:' source directory of the input package: $PACKAGE."
    exit 1
fi
[[ "$DEBUG" ]] && eups list | grep "^$PACKAGE "
PACKAGE_LOCAL_VERSION=`eups list -s $PACKAGE | awk '{print $1}'`
[[ "$DEBUG" ]] && echo "PACKAGE: $PACKAGE  PACKAGE_LOCAL_VERSION: $PACKAGE_LOCAL_VERSION"
cd $WORK_PWD


#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
step " Bootstrap $PACKAGE Dependency Chain"

BOOT_DEPS="$WORK_PWD/buildbot_tVt_bootstrap"
touch  $BOOT_DEPS
if [ $? != 0 ]; then
   print_error "Failed to create temp file: $BOOT_DEPS for dependency sequencing.\nTest of $PACKAGE failed before it started."
   exit 1
fi
TEMP_FILE="$WORK_PWD/buildbot_tVt_temp"
touch  $TEMP_FILE
if [ $? != 0 ]; then
   print_error "Failed to create temp file $TEMP_FILE for dependency sequencing.\nTest of $PACKAGE failed before it started."
   exit 1
fi
python ${0%/*}/gitOrderDependents.py -s  -t $TEMP_FILE $PACKAGE $PACKAGE_LOCAL_VERSION > $BOOT_DEPS
#OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO
# is there a reason why the exit status of this cmd isn't checked?
#OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO


COUNT=0
while read LINE; 
do
    print "   $COUNT  $LINE"
    (( COUNT++ ))
done < $BOOT_DEPS

step "Bootstrap $PACKAGE dependency tree"
while read CUR_PACKAGE CUR_VERSION CUR_DETRITUS; do
    cd $WORK_PWD
    step "Fetch $CUR_PACKAGE $CUR_VERSION to boostrap dependency list for $PACKAGE"
    #++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    # setup packages so correct dependency tree is created
    package_is_special $CUR_PACKAGE
    if [ $? = 0 ] ; then 
        continue; 
    fi
    package_is_external ${CUR_PACKAGE}
    if [ $? = 0 ]; then 
        # 2Dec11 RAA Swapped out for Robert's debug request tracking /lsst/home/buildbot/.eups/ups_db/Linux64.pickleDB1_3_0 error
        #pretty_execute "setup --debug=raise -v -v -v -j $CUR_PACKAGE $CUR_VERSION"
         pretty_execute "setup -j $CUR_PACKAGE $CUR_VERSION"
         if [ $RETVAL != 0 ]; then
             print "Warning: unable to eups-setup: $CUR_PACKAGE $CUR_VERSION, during bootstrap of dependency tree. Not fatal until accurate dependency tree is built."
         fi
        continue; 
    fi

    # -----------------------------------
    # -- Prepare SCM directory for build --
    # -----------------------------------

    prepareSCMDirectory $CUR_PACKAGE "BOOTSTRAP"
    if [ $RETVAL != 0 ]; then
        print_error="Failed to extract source directory for $CUR_PACKAGE."
        exit 1
    fi

    # -------------------------------
    # -- setup for a package build --
    # -------------------------------
    cd $SCM_LOCAL_DIR
    pretty_execute "setup -r . -j"
    #OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO
    # How do we feel about a failure to setup the LOCAL dir for an LSST Package
    # during the initial dependency tree setup?
    #OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO
    eups list  | grep "^$CUR_PACKAGE "
    cd $WORK_PWD
    
# -- Loop around to next entry in bootstrap dependency list --
done < "$BOOT_DEPS"

eups list -s

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
step "Generate accurate dependency tree for $PACKAGE build"
REAL_DEPS="$WORK_PWD/buildbot_tVt_real"
touch $REAL_DEPS
if [ $? != 0 ]; then
   print_error "Failed to create temporary file for dependency sequencing.\nTest of $PACKAGE failed before it started."
   exit 1
fi
TEMP_FILE="$WORK_PWD/buildbot_tVt_realtemp"
touch $TEMP_FILE
if [ $? != 0 ]; then
   print_error "Failed to create temp file $TEMP_FILE for dependency sequencing.\nTest of $PACKAGE failed before it started."
   exit 1
fi
python ${0%/*}/gitOrderDependents.py -s -t $TEMP_FILE $PACKAGE $PACKAGE_LOCAL_VERSION > $REAL_DEPS
#OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO
# is there a reason why the exit status of this cmd isn't checked?
#OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO

COUNT=0
while read LINE; 
do
    print "   $COUNT  $LINE"
    (( COUNT++ ))
done < $REAL_DEPS


while read CUR_PACKAGE CUR_VERSION CUR_DETRITUS; do
    cd $WORK_PWD
    #++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    step "Install accurate dependency $CUR_PACKAGE"

    # -- Process special lsst packages  
    package_is_special $CUR_PACKAGE
    if [ $? = 0 ]; then
        # Attempt setup of named package/version; don't exit if failure occurs
        setup -j $CUR_PACKAGE $CUR_VERSION
        if [ $? = 0 ]; then
            print "Special-case dependency: $CUR_PACKAGE $CUR_VERSION  successfully installed"
        else
            print "Warning: Special-case dependency: $CUR_PACKAGE $CUR_VERSION  not available. Continuing without it."
        fi
        continue
    fi

    # -- Process external packages  via lsstpkg --
    package_is_external ${CUR_PACKAGE}
    if [ $? = 0 ]; then
        #ooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
        #   B U G   B U G     B U G      B U G     B U G     B U G
        #  Check if new eups always matches Externals on Current  
        #   		instead of  Current[EUPS DB] reported from 'eups list'
        #   B U G   B U G     B U G      B U G     B U G     B U G
        #ooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
        print "Installing external package: $CUR_PACKAGE $CUR_VERSION"
        eups list $CUR_PACKAGE $CUR_VERSION
        if [ $CUR_VERSION != "current" ]; then
            if [ `eups list -q $CUR_PACKAGE $CUR_VERSION | wc -l` = 0 ]; then
                INSTALL_CMD="lsstpkg install $CUR_PACKAGE $CUR_VERSION"
                pretty_execute $INSTALL_CMD
                if [ $RETVAL != 0 ]; then
                    FAIL_MSG="Failed to install $CUR_PACKAGE $CUR_VERSION with lsstpkg."
                    print_error $FAIL_MSG
                    emailFailure "$CUR_PACKAGE" "$CUR_VERSION" "$BUCK_STOPS_HERE"
                    exit 1
                else
                    print "External dependency: $CUR_PACKAGE, successfully installed."
                fi
            fi
        else  
            # if dependency just needs 'current', not specific rev, go with it
            # -- SWAPPED  20 Nov 2011 
            if [ `eups list -q $CUR_PACKAGE -c | wc -l` = 0 ]; then
                FAIL_MSG="Failed to setup external dependency: $CUR_PACKAGE.\nAn 'lsstpkg install --current' version was not found."
                print_error $FAIL_MSG
                emailFailure "$CUR_PACKAGE" "$CUR_VERSION" "$BUCK_STOPS_HERE"
                exit 1
            fi
            CUR_VERSION=""
        fi
        # 2Dec11 RAA Swapped out for Robert's debug request tracking /lsst/home/buildbot/.eups/ups_db/Linux64.pickleDB1_3_0 error
        #pretty_execute "setup --debug=raise -v -v -v  -j $CUR_PACKAGE $CUR_VERSION"
        pretty_execute "setup -j $CUR_PACKAGE $CUR_VERSION"
        if [ $RETVAL != 0 ]; then
            FAIL_MSG="Failed to setup external dependency: $CUR_PACKAGE $CUR_VERSION."
            print_error $FAIL_MSG
            emailFailure "$CUR_PACKAGE" "$CUR_VERSION" "$BUCK_STOPS_HERE" 
            exit 1
        fi
        print "External dependency: $CUR_PACKAGE $CUR_VERSION, successfully installed."
        continue
    fi



    # -----------------------------------
    # -- Prepare SVN directory for build --
    # -----------------------------------
    prepareSCMDirectory $CUR_PACKAGE "BUILD"
    if [ $RETVAL != 0 ]; then
        FAIL_MSG="Failed to extract source directory for $CUR_PACKAGE."
        print_error $FAIL_MSG
        emailFailure "$CUR_PACKAGE" "$REVISION" "$BUCK_STOPS_HERE" 
        exit 1
    fi

    # ---------------------------------------------------------------------
    # --  BLOCK1 -  this assumes that when NoTest is taken, that only a 
    # --            compilation is required and not a reload to check 
    # --            altered lib signatures or dependencies.
    # ---------------------------------------------------------------------
    print "cur_package is $CUR_PACKAGE   revision is $REVISION"
    #if  [ "$PACKAGE" != "$CUR_PACKAGE" -a  -f $SCM_LOCAL_DIR/BUILD_OK ] ; then
    if  [ -f $SCM_LOCAL_DIR/BUILD_OK ] ; then
        print "Local src directory is marked BUILD_OK"
        [[ "$DEBUG" ]]  &&  eups list $CUR_PACKAGE
        pretty_execute "setup -j  $CUR_PACKAGE $REVISION"
        [[ "$DEBUG" ]]  &&  eups list $CUR_PACKAGE
        if [ $RETVAL = 0 ] ; then
            print "Package/revision is already eups-installed. Skipping build."
            continue
        fi
    fi

    # ----------------------------------------------------------------
    # -- Rest of build work is done within the package's source directory --
    # ----------------------------------------------------------------
    cd $SCM_LOCAL_DIR 
    rm -f NEEDS_BUILD

    # -------------------------------
    # -- BLOCK 2  see note in BLOCK1
    # -- setup for a package build --
    # -------------------------------
    #if [ -f BUILD_OK ] ; then
    #   setup -j $CUR_PACKAGE $REVISION
    #   print "$CUR_PACKAGE previously built without error; skipping rebuild."
    #   continue
    #fi
    pretty_execute "setup -r . -k "
    pretty_execute "eups list -s"

    BUILD_STATUS=0

    # build libs; then build tests; then install.
    scons_tests $CUR_PACKAGE
    pretty_execute "scons -j $PARALLEL opt=3 python"
    if [ $RETVAL != 0 ]; then
        print_error "Failure of Build/Load: $CUR_PACKAGE $REVISION"
        BUILD_STATUS=2
    elif [ $DO_TESTS = 0 -a "$SCONS_TESTS" = "tests" -a -d tests ]; then 
        # Built libs OK, want Tests built and run
	# don't run these in parallel, because some tests depend on other
	# binaries to be built, and there's a race condition that will cause
	# the tests to fail if they're not built before the test is run.
        pretty_execute "scons opt=3 tests"
        FAILED_COUNT=`eval "find tests -name \"*.failed\" $SKIP_THESE_TESTS | wc -l"`
        if [ $FAILED_COUNT != 0 ]; then
            print_error "One or more required tests failed:"
            pretty_execute -anon 'find tests -name "*.failed"'
            # cat .failed files to stdout
            for FAILED_FILE in `find tests -name "*.failed"`; do
                echo "================================================" 
                echo "Failed unit test: $PWD/$FAILED_FILE" 
                cat $FAILED_FILE
                echo "================================================"
            done
            print_error "Failure of 'tests' Build/Run for $CUR_PACKAGE $REVISION"
            BUILD_STATUS=4
        else   # Built libs OK, ran tests OK, now eups-install
            pretty_execute "scons  version=$REVISION opt=3 install current declare python"
            if [ $RETVAL != 0 ]; then
                print_error "Failure of install: $CUR_PACKAGE $REVISION"
                BUILD_STATUS=3
            fi
            print "Success of Compile/Load/Test/Install: $CUR_PACKAGE $REVISION"
        fi
    else  # Built libs OK, no tests wanted|available, now eups-install
            pretty_execute "scons version=$REVISION opt=3 install current declare python"
            if [ $RETVAL != 0 ]; then
                print_error "Failure of install: $CUR_PACKAGE $REVISION"
                BUILD_STATUS=1
            fi
            print "Success during Compile/Load/Install with-tests: $CUR_PACKAGE $REVISION"
    fi

    print "BUILD_STATUS status after test failure search: $BUILD_STATUS"
    # Archive log if explicitly requested on success and always on failure.
    if [ "$BUILD_STATUS" -ne "0" ]; then
        # preserve config log 
        LOG_FILE="config.log"
        pretty_execute pwd
        if [ "$LOG_DEST" ]; then
            if [ -f "$LOG_FILE" ]; then
                set -x
                copy_log ${CUR_PACKAGE}_$REVISION/$LOG_FILE $LOG_FILE $LOG_DEST_HOST $LOG_DEST_DIR ${CUR_PACKAGE}/$REVISION $LOG_URL
                set +x
            else
                print "No $LOG_FILE present."
            fi
        else
            print "No archive destination provided for log file."
        fi
    fi

    #----------------------------------------------------------
    # -- return to primary work directory  --
    #----------------------------------------------------------
    cd $WORK_PWD

    # Time to exit due to build failure of a dependency
    if [ "$BUILD_STATUS" -ne "0" ]; then
        # Get Email List for Package Owners (returned in $PACKAGE_OWNERS)
        fetch_package_owners $CUR_PACKAGE
        SEND_TO="$BUCK_STOPS_HERE"
        if [ "$CUR_PACKAGE" == "$PACKAGE" ]; then
            SEND_TO="$PACKAGE_OWNERS"
        fi

        FAIL_MSG="A build of dependency: $CUR_PACKAGE (version: $REVISION) failed.\nFailed to build HEAD-vs-HEAD version of $PACKAGE due to failed build of this dependency.\n\n"
        print_error $FAIL_MSG
        fetch_blame_data $SCM_LOCAL_DIR $WORK_PWD 
        emailFailure "$CUR_PACKAGE" "$REVISION"  "$SEND_TO" 
        clear_blame_data

        #OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO
        # I can't figure out why this is necessary.  If they weren't setup
        # correctly, they were probably LOCAL: and will thus disappear on exit
        #OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO
        #   Following only necessary if failed during scons-install step
        if [ "`eups list  $CUR_PACKAGE $REVISION -s &> /dev/null`" = "0" ]; then
            pretty_execute "setup -u -j $CUR_PACKAGE $REVISION"
        fi
        if [ "`eups list  $CUR_PACKAGE $REVISION -c &> /dev/null`" = "0" ]; then
            pretty_execute "eups undeclare -c $CUR_PACKAGE $REVISION"
        fi
        print_error "Exiting since $CUR_PACKAGE failed to build/install successfully"
        #OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO
        exit 1
    fi

    # For production build, setup each successful install 
    print "-------------------------"
    setup -j $CUR_PACKAGE $REVISION
    if [ $? != 0 ]; then
        print ""
    fi
    eups list -v $CUR_PACKAGE $REVISION
    print "-------------------------"
    touch $SCM_LOCAL_DIR/BUILD_OK
    [ $? != 0 ] && print "Failed to set flag: $SCM_LOCAL_DIR/BUILD_OK" 



# -------------------------------------------------
# -- Loop around to next entry in dependency list --
# -------------------------------------------------
done < "$REAL_DEPS"

if [ $DO_TESTS = 0 ]; then
    print "Successfully built and tested trunk-vs-trunk version of $PACKAGE"
else
    print "Successfully built, but not tested, trunk-vs-trunk version of $PACKAGE"
fi
exit 0
