#!/usr/bin/python

###
# bootstrap.py - output all the package names and current master git 
#                hash tags for packages
#
import os, sys

class PackageList:

    def __init__(self,excludeFile):
        ##
        # current_list is the URL of the manifest for all git repositories.
        #
        current_list = "http://dev.lsstcorp.org/cgi-bin/build/repolist.cgi"
        
        ##
        # # F Y I:
        # # Following is content of cgi script accessed in 'current_list':
        # REPODIR=/lsst_ibrix/gitolite/repositories/LSST/DMS
        # echo "Content-type: text/html"
        # echo
        # /bin/ls -d $REPODIR/*git | sed 's/\/lsst_ibrix\/gitolite\/repositories\/LSST\/DMS\///'
        # # Problem is '$REPODIR/*git'  excludes all the git-packages 
        # # which are more than one level from  LSST/DMS.


        
        #
        stream = os.popen("curl -s "+current_list)
        
        ##
        # read all the packages of the stream, and put them into a set, removing
        # the excluded packages.
        #
        
        pkgs = stream.read().split()
        stream.close()

        
        # read in a list of git packages we know are excluded.
        #excluded_internal_list = "/lsst/home/buildbot/RHEL6/gitwork/etc/excludedGit_<lang>.txt"
        excluded_internal_list = excludeFile
        stream = open(excluded_internal_list,"r")
        excluded_internal_pkgs = stream.read().split()
        stream.close()

        self.pkg_list = []
        for name in pkgs:
            if (name in excluded_internal_pkgs) == False:
                index = name.rfind(".git")
                self.pkg_list.append(name[:index])
        
        
    def getPackageList(self):
        return self.pkg_list

#========================================================================
if len(sys.argv) < 3:
    sys.stderr.write("FATAL: Usage: %s <git-branch> <excluded git repos file>" % (sys.argv[0]))
    sys.exit(1)

gitBranch = sys.argv[1]    

#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/
#      JUST WHERE IS THE ERROR CHECKING ON THIS INPUT PARAMETER????
excludedGitRepositories = sys.argv[2]
#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/


##
# open each of the packages at the distribution stack URL, look up the hash
# tag for <branch>, and output the package name and hash tag to STDOUT;
# if <branch>'s hash tag is not found, look up the hash tag for 'master', 
# and output the package name and hash tag to STDOUT.
#
p = PackageList(excludedGitRepositories)
ps = p.getPackageList()
for pkg in ps:
    gitURL = "git@git.lsstcorp.org:LSST/DMS/"+pkg+".git"
    try:
        # Does named  <branch> exist?
        stream=os.popen("git ls-remote --refs -h "+ gitURL +" | grep refs/heads/"+ gitBranch +"$ | awk '{print $1}'")
        hashTag = stream.read()
        strippedHashTag = hashTag.strip()
        fromBranch = gitBranch
        # If not, then fetch from 'master'?
        if not strippedHashTag:
            stream=os.popen("git ls-remote --refs -h "+ gitURL +" | grep refs/heads/master | awk '{print $1}'")
            hashTag = stream.read()
            strippedHashTag = hashTag.strip()
            fromBranch = "master"

        if strippedHashTag:
            print pkg+" "+strippedHashTag+" "+fromBranch
        else:
            sys.stderr.write('FAILURE: Failed to find git hash code for: %s\n' % pkg)
    except IOError:
        sys.stderr.write('FAILURE: IOError whilst acquiring git hash code for: %s\n' % pkg)
        pass

