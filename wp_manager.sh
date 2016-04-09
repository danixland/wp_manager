#! /bin/bash

# Version 0.7.3

#------------------------------------------------------------------------------
# 								wp_manager.sh
# 				by Danilo 'danix' Macri <danix@danixland.net>
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
#								### EXIT STATUSES ###
#------------------------------------------------------------------------------
STATUSDISPLAY=160

E_NOARGS=170
E_WRITECONFERR=171
E_MULTIPLEINSTANCES=172
E_MULTIPLESWITCHES=173
E_SETTINGSERRORS=174
E_NOVHOSTCONF=175
E_NEWSITEEXISTS=176

#------------------------------------------------------------------------------
#								### OPTIONS ###
#------------------------------------------------------------------------------

# path to the config file. Can be relative to the script or absolute.
# RELATIVE SCRIPTCONFIG:
SCRIPTCONFIG=${SCRIPTCONFIG:-"$(dirname $0)/$(basename $0 .sh).conf"}
# ABSOLUTE SCRIPTCONFIG:
#SCRIPTCONFIG=${SCRIPTCONFIG:-"/etc/$(basename $0 .sh).conf"}

# Read the configfile if it exists
[ -f ${SCRIPTCONFIG} ] && . ${SCRIPTCONFIG}

# Script defaults - edits should go into the config file
set_defaults() {
# Binaries to use:
SVN=${SVN:-"/usr/bin/svn"}

# Set this variable to your server's DocumentRoot.
WEBSERVER=${WEBSERVER:-"/var/www/htdocs"}

# Directory were the Apache config files are stored.
SERVERADMIN=${SERVERADMIN:-"admin@some.url"}

# The apache config file
APACHECONF=${APACHECONF:-"/etc/httpd/httpd.conf"}

# The Virtual Hosts config file.
# If your distro uses only the main file "httpd.conf" to store the vhosts
# settings leave this parameter blank.
VHOSTCONF=${VHOSTCONF:-"$(dirname $APACHECONF)/extra/httpd-vhosts.conf"}

# This is the interface where the VHost will be listening for connections.
# All VHosts will rely on this setting using name based vhosts for our setup.
VHOSTLISTEN=${VHOSTLISTEN:-"*:80"}

# The directory containing the local svn copy of the WordPress.org
# repository for WordPress itself as well as some other useful plugins.
# In this directory we'll also store some template files to be installed
# when we setup the vhost.
# By default it's sitting in the same directory that is containing the
# DocumentRoot, so in our case, by default will be in /var/www/.wp-base
BASEDIR=${BASEDIR:-".wp-base"}

# This is the mysql username that will be in charge of all the databases
# created by this script
DBUSER=${DBUSER:-""}

# The password for the mysql username
DBPASS=${DBPASS:-""}

# Change this if your mysql database is on a different server than the one
# where Apache is running
# WARNING - NEEDS TESTING
HOST=${HOST:-"localhost"}

# Shall we clean the tmpdir after every use?
CLEANUP=${CLEANUP:-"yes"}

} # end set_defaults, do not change this line.

set_defaults

#------------------------------------------------------------------------------
# No need to modify anything from here on.
#------------------------------------------------------------------------------

# Here we'll store the temporary files used during this script operation.
TMPDIR=${TMPDIR:-"/tmp/wp_manager"}.$$
# Let's prevent the script from running more than one instance at a time.
PIDFILE=/var/tmp/$(basename $0 .sh).pid
# This variable will hold a list of VHosts created by the script
VHOSTLIST=$(grep "# BEGIN WP_MANAGER VHOST" ${VHOSTCONF} | cut -d " " -f 5)

# WordPress svn address
WORDPRESS=${WORDPRESS:-"https://core.svn.wordpress.org/trunk/"}

#------------------------------------------------------------------------------
#						### create tmd directory ###
#------------------------------------------------------------------------------
mktmp() {
	# check for tmpdir and delete it if existing, then recreate it
	if [ -d ${TMPDIR} ]; then
		rm -rf $TMPDIR
		mkdir $TMPDIR
	else
		mkdir $TMPDIR
	fi
}

#------------------------------------------------------------------------------
#							### Display help text ###
#------------------------------------------------------------------------------
usage() {
	echo "USAGE:"
	echo `basename $0` "-h"
	echo "this shows the help and exits"; echo
	echo `basename $0` "-b"
	echo "updates all base files like WordPress local repo and plugins"; echo
	echo `basename $0` "-i <new directory name>"
	echo "install the VHost 'new directory name'"; echo
	echo `basename $0` "-d <directory name>"
	echo "Deletes the VHost 'directory name' and all of its data"; echo
	echo `basename $0` "-u"
	echo "updates all VHosts containing a WordPress install"; echo
	rm -f $PIDFILE
	exit $E_NOARGS
}

#------------------------------------------------------------------------------
#							### Generate config file ###
#------------------------------------------------------------------------------
generateconf() {
	if [ -r $SCRIPTCONFIG ]; then
		echo "Backing up current '${SCRIPTCONFIG}' to ${SCRIPTCONFIG}.$(date +%Y%m%d_%H%M)."
		mv -f ${SCRIPTCONFIG} ${SCRIPTCONFIG}.$(date +%Y%m%d_%H%M)
	fi
	echo "Writing '${SCRIPTCONFIG}'."
	sed  -n '/^set_defaults() {/,/^} # end set_defaults, do not change this line./p' $0 \
		| grep -v set_defaults \
		| sed -e 's/^\([^=]*\)=\${\1:-\([^}]*\)}/\1=\2/' \
		> ${SCRIPTCONFIG}
	if [ -r ${SCRIPTCONFIG} ]; then
		echo "${SCRIPTCONFIG} written correctly. Exiting now."
		rm -f $PIDFILE
		exit 0
	else
		echo "Could not write '${SCRIPTCONFIG}'. Exiting."
		rm -f $PIDFILE
		exit $E_WRITECONFERR
	fi
}

#------------------------------------------------------------------------------
#								### Setup Check ###
#------------------------------------------------------------------------------
check_setup() {
	ERRORMSG=""

	# we need to check that svn is installed before anything else
	if [ ! -x ${SVN} ]; then
		ERRORMSG+="\"${SVN}\" executable not found, check your \$SVN setting."
	fi
	# check the DocRoot
	if [ ! -d ${WEBSERVER} ]; then
		ERRORMSG+="\n\"${WEBSERVER}\" is not a directory, check your \$WEBSERVER setting."
	fi
	# Apache conf directory check
	if [ ! -r ${APACHECONF} ]; then
		ERRORMSG+="\nCannot read \"${APACHECONF}\", check your \$APACHECONF setting."
	else
		# check the VHosts file
		if [[ ${VHOSTCONF} ]]; then
			if [ ! -r ${VHOSTCONF} ]; then
				ERRORMSG+="\n\"${VHOSTCONF}\" can't be read, check your \$VHOSTCONF setting."
			fi
		fi
	fi
	# check if we have a username and password, or we won't be able to install everything
	if [[ -z $DBUSER || -z $DBPASS ]]; then
		ERRORMSG+="\n\"\$DBUSER\" or \"\$DBPASS\" are not set. This script won't be able to install new VHosts without those settings."
	fi
	if [[ $ERRORMSG != "" ]]; then
		echo "we've found some errors in your configuration."
		echo "It is advisable to create a config file running '$(basename $0) -w'"
		echo -e "and edit it to suit your current server configuration. \n"
		echo -e "CONFIGURATION ERRORS:"
		echo -e $ERRORMSG;
		rm -f $PIDFILE
		exit $E_SETTINGSERRORS
	else
		echo -e "SETUP CHECK PASSED."
	fi
}

#------------------------------------------------------------------------------
#							### Setup base files ###
#------------------------------------------------------------------------------
base_setup() {
	directory=$(dirname ${WEBSERVER})/${BASEDIR}
	echo -e "installing base files inside '${directory}'"
	if [ ! -d $directory ]; then
		echo "creating base directory '${directory}'"
		mkdir -p $directory
	else
		echo -e "${directory} already exists.\n"
		read -p "do you wish to rebuild it? [y/n] " -n 1 -r; echo
		if [[ ! $REPLY =~ ^[Yy]$ ]]; then
			exit $USERABORTED
		else
			echo "rebuilding base directory '${directory}'"
			rm -rf $directory && mkdir $directory
		fi
	fi
	# let's get salty! we'll need those keys in a minute
	echo "Downloading secret-keys from WordPress.org API"
	wget -O ${TMPDIR}/wp.keys https://api.wordpress.org/secret-key/1.1/salt/
	echo "Downloading WordPress from svn"
	${SVN} co ${WORDPRESS} ${directory}/WP
	echo "creating base wp-config.php"
	cp ${directory}/WP/wp-config-sample.php ${TMPDIR}/wp-config.php
	# substitute username and password with our settings
	sed -i "s/username_here/${DBUSER}/" ${TMPDIR}/wp-config.php
	sed -i "s/password_here/${DBPASS}/" ${TMPDIR}/wp-config.php
	# copy the secret keys into our file
	sed -i "/#@-/r ${TMPDIR}/wp.keys" ${TMPDIR}/wp-config.php
	sed -i "/#@+/,/#@-/d" ${TMPDIR}/wp-config.php
	# activate WP_DEBUG
	sed -i "s/false)/true)/" ${TMPDIR}/wp-config.php
	# put the wp-config.php file back in its place
	cp ${TMPDIR}/wp-config.php ${directory}/wp-config.php
}

#------------------------------------------------------------------------------
#							### Update base files ###
#------------------------------------------------------------------------------
base_update() {
	echo "updating base files"
}

#------------------------------------------------------------------------------
#							### List our VHosts ###
#------------------------------------------------------------------------------
list_vhosts() {
	VHOSTCOUNT=$(echo ${VHOSTLIST} | wc -w)
	echo -e "This script has generated ${VHOSTCOUNT} Virtual Hosts.\n"
	echo $VHOSTLIST
}

check_installed() {
	new_site=$1
	echo "${VHOSTLIST}" | grep -q "\b${new_site}\b"
	if [ $? == 0 ]; then
		echo "${new_site} already exists. Exiting now."
		rm -rf $TMPDIR
		rm -f $PIDFILE
		exit $E_NEWSITEEXISTS
	fi
}

#------------------------------------------------------------------------------
#							### Install new VHost ###
#------------------------------------------------------------------------------
install_new() {
	new_site=$1
	check_installed $new_site
	echo "installing $new_site"
	# do we have a vhost-conf file? If yes copy it to our tmp directory and edit
	# it there before putting it back in its place, else work on the httpd.conf
	# in the same way
	if [ $VHOSTCONF ]; then
		TMPVHOSTCONF=${TMPDIR}/$(basename ${VHOSTCONF}).$(date +%Y%m%d_%H%M)
		cp ${VHOSTCONF} $TMPVHOSTCONF
		cat >> ${TMPVHOSTCONF} <<EOVH
# BEGIN WP_MANAGER VHOST ${new_site}
<VirtualHost ${VHOSTLISTEN}>
    ServerAdmin ${SERVERADMIN}
    DocumentRoot "${WEBSERVER}/${new_site}"
    ServerName ${new_site}
    ErrorLog "/var/log/httpd/${new_site}-error_log"
    CustomLog "/var/log/httpd/${new_site}-access_log" common
</VirtualHost>
# END WP_MANAGER VHOST ${new_site}

EOVH
		# let's put the file back in its place but we can make a backup first
		echo "Backing up $(basename ${VHOSTCONF}) to $(basename ${VHOSTCONF}).$(date +%Y%m%d_%H%M)"
		mv ${VHOSTCONF} ${VHOSTCONF}.$(date +%Y%m%d_%H%M)
		cp ${TMPVHOSTCONF} ${VHOSTCONF}
		[ $? -eq 0 ] && echo "${VHOSTCONF} modified successfully"
		echo "Adding MYSQL database and user"
		if [ -r "/root/.my.cnf" ]; then
			mysql -uroot <<MYSQLSCRIPT
CREATE DATABASE ${new_site};
CREATE USER '${new_site}'@'localhost' IDENTIFIED BY '${new_site}';
GRANT ALL PRIVILEGES ON ${new_site}.* TO '${new_site}'@'localhost';
FLUSH PRIVILEGES;
MYSQLSCRIPT
		else
			echo "Please enter the password for mysql root user:"
			read mysqlrootpass
			mysql -uroot -p${mysqlrootpass} <<MYSQLSCRIPT
CREATE DATABASE ${new_site};
CREATE USER '${new_site}'@'localhost' IDENTIFIED BY '${new_site}';
GRANT ALL PRIVILEGES ON ${new_site}.* TO '${new_site}'@'localhost';
FLUSH PRIVILEGES;
MYSQLSCRIPT
		fi
		[ $? -eq 0 ] && echo "database and user created successfully"
		echo "installing WordPress"
#		[ ! -d ${WEBSERVER}/${new_site} ] && mkdir -p ${WEBSERVER}/${new_site}


	else # I'll have to work on using httpd.conf only
		echo "using only httpd.conf is not yet working."
		exit $E_NOVHOSTCONF
	fi
}

#------------------------------------------------------------------------------
#							### Update VHosts ###
#------------------------------------------------------------------------------
update() {
	echo "updating"
}

#------------------------------------------------------------------------------
#							### Delete selected VHost ###
#------------------------------------------------------------------------------
delete() {
	echo "deleting $1"
}

#------------------------------------------------------------------------------
#							### Ready? Set, GO!! ###
#------------------------------------------------------------------------------

# Make sure the PID file is removed when we kill the process
trap 'rm -f $PIDFILE; exit 1' TERM INT

# check $PIDFILE and abort if one exists
if [ -e $PIDFILE ]; then
	echo "Another instance ($(cat $PIDFILE)) still running?"
	echo "If you are sure that no other instance is running, delete the lockfile"
	echo "'${PIDFILE}' and re-start this script."
	echo "Aborting now..."
	exit $E_MULTIPLEINSTANCES
else
	echo $$ > $PIDFILE

	# Parse the commandline options:
	if (( $# == 0 )); then
		if [ ! -r ${SCRIPTCONFIG} ]; then
			echo "WARNING - NO CONFIGURATION FILE FOUND."
			echo "It is advisable to create a config file running '$(basename $0) -w'"
			echo "and edit it to suit your current server configuration or this script"
			echo -e "won't let you operate. \n"
		fi
		echo -e "CURRENT CONFIGURATION: \n"
		echo -e "Webserver\t\t = $WEBSERVER"
		echo -e "Apache config\t\t = $APACHECONF"
		echo -e "Server Admin\t\t = $SERVERADMIN"
		echo -e "vhost config file\t = $VHOSTCONF"
		echo -e "Base Directory\t\t = $BASEDIR"
		echo -e "tmp Directory\t\t = $TMPDIR"
		echo -e "Username\t\t = $DBUSER"
		echo -e "Password\t\t = $DBPASS"
		echo -e "Host\t\t\t = $HOST"
		echo -e "database name\t\t = $DB_NAME \n"
		check_setup
		rm -f $PIDFILE; exit $STATUSDISPLAY
	else
		while getopts "i:d:bslhuw" Option
		do
			case $Option in
				b ) check_setup
					base_update
					break
					;;
				i ) check_setup
					mktmp
					install_new ${OPTARG}
					break
					;;
				d ) check_setup
					delete ${OPTARG}
					break
					;;
				u ) check_setup
					update
					break
					;;
				s ) check_setup
					mktmp
					base_setup
					;;
				l ) list_vhosts
					;;
				w ) generateconf
					;;
				h ) usage
					;;
				* ) usage
					;; # default behaviour
			esac
		done

		# End of option parsing.
		shift $(($OPTIND - 1))

		#  $1 now references the first non option item supplied on the command line
		#  if one exists.
		# ---------------------------------------------------------------------------
	fi

fi

if [ $CLEANUP == "yes" ]; then
	[ -d $TMPDIR ] && rm -rf $TMPDIR
fi
rm -f $PIDFILE
exit 0

