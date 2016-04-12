#! /bin/bash

# Version 0.7.4

#------------------------------------------------------------------------------
# 								wp_manager.sh
# 				by Danilo 'danix' Macri <danix@danixland.net>
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
#								### SCRIPT COLORS ###
#------------------------------------------------------------------------------
RED='\E[31;40m'
GREEN='\E[32;40m'
YELLOW='\E[33;40m'
BLUE='\E[34;40m'
COLOR_RESET=$(tput sgr0)

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
E_NEWSITEDIREXISTS=177
E_NOVHOSTSUPDATABLE=178

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

# The admin email for your server
SERVERADMIN=${SERVERADMIN:-"admin@some.url"}

# The apache config file
APACHECONF=${APACHECONF:-"/etc/httpd/httpd.conf"}

# All Files inside the DocumentRoot for the VHosts will be owned
# by this user/group, so it is advisable to make your usual user
# part of the $APACHEGROUP to be able to modify files in the VHosts
# The server user under which the apache executable is running
APACHEUSER=${APACHEUSER:-"apache"}
# The server group under which the apache executable is running
APACHEGROUP=${APACHEGROUP:-"apache"}

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

# Present Working Directory
PWD=$(pwd)
# Here we'll store the temporary files used during this script operation.
TMPDIR=${TMPDIR:-"/tmp/wp_manager"}.$$
# Let's prevent the script from running more than one instance at a time.
PIDFILE=/var/tmp/$(basename $0 .sh).pid
# This variable will hold a list of VHosts created by the script
VHOSTLIST=$(grep "# BEGIN WP_MANAGER VHOST" ${VHOSTCONF} | cut -d " " -f 5)

# Developer plugins we want installed on our VHosts
WP_PLUGINS=(
	"developer"
	"debug-bar"
	"debug-bar-console"
	"debug-bar-cron"
	"debug-bar-extender"
	"rewrite-rules-inspector"
	"log-deprecated-notices"
	"monster-widget"
	"user-switching"
	"piglatin"
	"rtl-tester"
	"regenerate-thumbnails"
	"simply-show-ids"
	"theme-test-drive"
	"theme-check"
	"wordpress-importer"
)

# WordPress svn address
WORDPRESS=${WORDPRESS:-"https://core.svn.wordpress.org/trunk/"}

# helper function that checks for already installed VHosts
check_installed() {
	new_site=$1
	echo "${VHOSTLIST}" | grep -q "\b${new_site}\b"
	if [ $? == 0 ]; then
		echo "${new_site} already exists. Exiting now."
		rm -f $PIDFILE
		exit $E_NEWSITEEXISTS
	fi
}

# Create tmd directory
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
# USAGE: $0 -h
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
# USAGE: $0 -w
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
		echo -e "${GREEN}${SCRIPTCONFIG} written correctly. Exiting now."
		echo -e ${COLOR_RESET}
		rm -f $PIDFILE
		exit 0
	else
		echo -e ${RED}
		echo "Could not write '${SCRIPTCONFIG}'. Exiting."
		echo -e ${COLOR_RESET}
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
		echo -e ${YELLOW}
		echo "we've found some errors in your configuration."
		echo "It is advisable to create a config file running '$(basename $0) -w'"
		echo -e "and edit it to suit your current server configuration. \n"
		echo -e ${RED}
		echo -e "CONFIGURATION ERRORS:"
		echo -e $ERRORMSG
		echo -e ${COLOR_RESET}
		rm -f $PIDFILE
		exit $E_SETTINGSERRORS
	else
		echo -e ${GREEN}
		echo -e "SETUP CHECK PASSED."
		echo -e ${COLOR_RESET}
	fi
}

#------------------------------------------------------------------------------
#							### Setup base files ###
#------------------------------------------------------------------------------
# USAGE: $0 -s
base_setup() {
	directory=$(dirname ${WEBSERVER})/${BASEDIR}
	echo -e "${BLUE}installing base files inside ${GREEN}'${directory}'"
	if [ ! -d $directory ]; then
		echo -e "${BLUE}creating base directory '${directory}'"
		mkdir -p $directory
	else
		echo -e "${YELLOW}${directory} already exists."
		echo -e "If you're trying to update your base directory you can run:"
		echo -e "${GREEN}'$(basename $0) -b'${YELLOW} without needing to rebuild.${BLUE}\n"
		read -p "do you really wish to rebuild ${directory}? [y/n] " -n 1 -r; echo -e ${COLOR_RESET}
		if [[ ! $REPLY =~ ^[Yy]$ ]]; then
			exit $USERABORTED
		else
			echo -e "${BLUE}rebuilding base directory ${GREEN}'${directory}'${COLOR_RESET}"
			rm -rf $directory && mkdir $directory
		fi
	fi
	# create patches directory
	mkdir ${directory}/patches
	# echo today's date in unix timestamp (no seconds)
	touch ${directory}/lastupdate && echo $(date -d $(date +"%Y-%m-%d") +%s) > ${directory}/lastupdate
	# let's get salty! we'll need those keys in a minute
	echo -e "${BLUE}Downloading secret-keys from WordPress.org API${COLOR_RESET}"
	wget -O ${TMPDIR}/wp.keys https://api.wordpress.org/secret-key/1.1/salt/
	echo -e "${BLUE}Downloading WordPress from svn${COLOR_RESET}"
	${SVN} co ${WORDPRESS} ${directory}/WP
	echo -e "${BLUE}creating base wp-config.php${COLOR_RESET}"
	cp ${directory}/WP/wp-config-sample.php ${TMPDIR}/wp-config.php
	# substitute username and password with our settings
	sed -i "s/username_here/${DBUSER}/" ${TMPDIR}/wp-config.php
	sed -i "s/password_here/${DBPASS}/" ${TMPDIR}/wp-config.php
	# copy the secret keys into our file
	sed -i "/#@-/r ${TMPDIR}/wp.keys" ${TMPDIR}/wp-config.php
	sed -i "/#@+/,/#@-/d" ${TMPDIR}/wp-config.php
	# activate WP_DEBUG and SAVEQUERIES
	sed -i "s/false)/true)/" ${TMPDIR}/wp-config.php
	sed -i "/define('WP_DEBUG'/ a define( 'SAVEQUERIES', true );" ${TMPDIR}/wp-config.php
	# put the wp-config.php file back in its place
	cp ${TMPDIR}/wp-config.php ${directory}/wp-config.php
	# download every plugin we need from svn inside PLUGINS directory
	echo -e "${BLUE}Downloading plugins${COLOR_RESET}"
	[ ! -d ${directory} ] && mkdir ${directory}/PLUGINS
	for plugin in "${WP_PLUGINS[@]}"; do
		echo -e "${BLUE}Downloading ${GREEN}${plugin}${COLOR_RESET}"
		${SVN} co https://plugins.svn.wordpress.org/${plugin}/trunk ${directory}/PLUGINS/${plugin}
	done
	echo -e "\n${GREEN}All base files have been installed successfully. Existing.${COLOR_RESET}"
}

#------------------------------------------------------------------------------
#							### Update base files ###
#------------------------------------------------------------------------------
# USAGE: $0 -b
base_update() {
	directory=$(dirname ${WEBSERVER})/${BASEDIR}
	# test last update - ideally this options needs to run once a day
	if [ -r ${directory}/lastupdate ]; then
		lastup=$(cat ${directory}/lastupdate)
		today=$(date $(date +"%Y-%m-%d") +%s)
		if [ $today -eq $lastup ]; then
			echo -e "${YELLOW}It appears that you updated less than 1 day ago.${BLUE}\n"
			read -p "do you really wish to continue the update? [y/n] " -n 1 -r; echo -e ${COLOR_RESET}
			if [[ ! $REPLY =~ ^[Yy]$ ]]; then
				exit $USERABORTED
			fi
		fi
	fi
	echo -e "${BLUE}Updating base files inside ${GREEN}'${directory}'"
	echo -e "${BLUE}Creating patch files inside ${GREEN}'${directory}/patches/'${COLOR_RESET}"
	[ -d ${directory}/patches ] && rm ${directory}/patches/*
	# now we have a clean old copy of WordPress
	${SVN} export ${directory}/WP ${TMPDIR}/WP.old
	# and a clean new copy here
	${SVN} up ${directory}/WP
	${SVN} export ${directory}/WP ${TMPDIR}/WP.new
	# let's create some patch files containing the name of all the modified files 
	# between the two versions of WP

# Find files existing only in one of the two versions, either new or old
#	diff -qr WP.old WP.new/ |grep Only | sed -e 's/Only in //' -e 's/: /\//'
	cd $TMPDIR
	# Get those files that needs to be deleted with: 
	diff -qr WP.old WP.new/ |grep Only |grep -e old | sed -e 's/Only in //' -e 's/: /\//' > ${directory}/patches/wp-delete.txt
	# And files that need to be added with:
	diff -qr WP.old WP.new/ |grep Only |grep -e new | sed -e 's/Only in //' -e 's/: /\//' >> wp-add-update.txt
	# And finally we can get those files that need to be updated with:
	diff -qr WP.old WP.new/ | cut -d " " -f 4 |grep WP. >> wp-add-update.txt
	sed 's/WP.new\///' < wp-add-update.txt > wp-patch.txt
	mkdir -p ${directory}/patches/wp-add
	mods=$(cat ${TMPDIR}/wp-patch.txt)
	cd WP.new
	for i in $mods;do
		cp --parents $i ${directory}/patches/wp-add/
	done
	cd $PWD

	echo -e "${BLUE}Updating plugins${COLOR_RESET}"
	for plugin_dir in $(/bin/ls ${directory}/PLUGINS); do
		echo -e "${BLUE}Updating ${GREEN}${plugin_dir}${COLOR_RESET}"
		${SVN} up ${directory}/PLUGINS/${plugin_dir}
	done
	echo $(date -d $(date +"%Y-%m-%d") +%s) > ${directory}/lastupdate
	echo -e "\n${GREEN}All base files have been updated successfully. Existing.${COLOR_RESET}"
}

#------------------------------------------------------------------------------
#							### List our VHosts ###
#------------------------------------------------------------------------------
# USAGE: $0 -l
list_vhosts() {
	VHOSTCOUNT=$(echo ${VHOSTLIST} | wc -w)
	echo -e "This script has generated ${VHOSTCOUNT} Virtual Hosts.\n"
	echo $VHOSTLIST
}

#------------------------------------------------------------------------------
#							### Install new VHost ###
#------------------------------------------------------------------------------
# USAGE: $0 -i new_site
install_new() {
	directory=$(dirname ${WEBSERVER})/${BASEDIR}
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
    <Directory /var/www/htdocs/${new_site}>
        DirectoryIndex index.php
        AllowOverride All
        Order Allow,deny
        Allow from all
        Require all granted
    </Directory>
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
CREATE DATABASE IF NOT EXISTS ${new_site};
GRANT ALL PRIVILEGES ON ${new_site}.* TO '${DBUSER}'@'localhost' IDENTIFIED BY '${DBPASS}';
FLUSH PRIVILEGES;
MYSQLSCRIPT
		else
			echo "Please enter the password for mysql root user:"
			read mysqlrootpass
			mysql -uroot -p${mysqlrootpass} <<MYSQLSCRIPT
CREATE DATABASE ${new_site};
GRANT ALL PRIVILEGES ON ${new_site}.* TO '${DBUSER}'@'localhost' IDENTIFIED BY '${DBPASS}';
FLUSH PRIVILEGES;
MYSQLSCRIPT
		fi
		[ $? -eq 0 ] && echo "database and user created successfully"
		echo "installing WordPress"
		if [ -d ${WEBSERVER}/${new_site} ]; then
			echo -e "${RED}The directory '${WEBSERVER}/${new_site}' already exists. Exiting now.${COLOR_RESET}"
			rm -f $PIDFILE
			exit $E_NEWSITEDIREXISTS
		else
			mkdir -p ${WEBSERVER}/${new_site}
			mkdir -p ${TMPDIR}/PLUGINS
			echo -e "${BLUE}Exporting WordPress files${COLOR_RESET}"
			${SVN} export ${directory}/WP ${TMPDIR}/WP
			echo -e "${BLUE}Exporting WordPress plugins${COLOR_RESET}"
			for plugin_dir in $(/bin/ls ${directory}/PLUGINS); do
				echo -e "${BLUE}Exporting ${GREEN}${plugin_dir}${COLOR_RESET}"
				${SVN} export ${directory}/PLUGINS/${plugin_dir} ${TMPDIR}/PLUGINS/${plugin_dir}
			done
			echo -e "${BLUE}installing WordPress files and plugins to ${GREEN}${new_site}${COLOR_RESET}"
			cp -R ${TMPDIR}/WP/* ${WEBSERVER}/${new_site}/
			cp -R ${TMPDIR}/PLUGINS/* ${WEBSERVER}/${new_site}/wp-content/plugins/
			# final edit to wp-config.php before installing it to $new_site
			cp ${directory}/wp-config.php ${TMPDIR}/wp-config.php
			sed -i "s/database_name_here/${new_site}/" ${TMPDIR}/wp-config.php
			cp ${TMPDIR}/wp-config.php ${WEBSERVER}/${new_site}/wp-config.php
		fi
		echo -e "${BLUE}Changing owner of ${GREEN}${new_site}${BLUE} to ${APACHEUSER}:${APACHEGROUP} ${COLOR_RESET}"
		chown -R ${APACHEUSER}:${APACHEGROUP} ${WEBSERVER}/${new_site}
		echo -e "${GREEN}A new website has been created and is awaiting for you."
		echo "It's now time to restart your apache webserver and enjoy WordPress at '${new_site}'."
		echo -e "${YELLOW}Don't forget to update your 'hosts' file on every client that is going to"
		echo "access this server on your lan."
		echo -e "${BLUE}You can use this command to modify the file /etc/hosts on your linux client:"
		echo -e "${GREEN}echo -e \"\$(hostname -i)\\\t\\\t${new_site}\" >> /etc/hosts${COLOR_RESET}"

	else # I'll have to work on using httpd.conf only
		echo -e "${RED}using only httpd.conf is not yet working.${COLOR_RESET}"
		exit $E_NOVHOSTCONF
	fi
}

#------------------------------------------------------------------------------
#							### Update VHosts ###
#------------------------------------------------------------------------------
# USAGE: $0 -u
update() {
	directory=$(dirname ${WEBSERVER})/${BASEDIR}
	todelete="${directory}/patches/wp-delete.txt"
	VHOSTS=$(echo ${VHOSTLIST})
	if [ -n "$VHOSTS" ]; then
		for site in $VHOSTS; do
			echo -e "${BLUE}Updating WordPress install on ${GREEN}${WEBSERVER}/$site${COLOR_RESET}"
			cd ${WEBSERVER}/$site
			if [ -s $todelete ]; then
				echo -e "${BLUE}Deleting obsolete files${COLOR_RESET}"
				for file in $(cat $todelete); do
					rm $file
				done
			fi
			echo -e "${BLUE}Updating WordPress files${COLOR_RESET}"
			cp -R ${directory}/patches/wp-add/* .
		done
	else
		echo -e "${YELLOW}no VHosts to update, Exiting.${COLOR_RESET}"
		cd $PWD
		rm -f $PIDFILE
		exit $E_NOVHOSTSUPDATABLE
	fi
	cd $PWD
	echo -e "${GREEN}aLL VHosts are up to date now.${COLOR_RESET}"
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
			echo -e ${YELLOW}
			echo "WARNING - NO CONFIGURATION FILE FOUND."
			echo "It is advisable to create a config file running '$(basename $0) -w'"
			echo "and edit it to suit your current server configuration or this script"
			echo -e "won't let you operate.${COLOR_RESET} \n"
		fi
		echo -e "${GREEN}CURRENT CONFIGURATION:${COLOR_RESET} \n"
		echo -e "Webserver\t\t = ${GREEN}$WEBSERVER${COLOR_RESET}"
		echo -e "Apache config\t\t = ${GREEN}$APACHECONF${COLOR_RESET}"
		echo -e "Apache user:group\t = ${GREEN}${APACHEUSER}:${APACHEGROUP}${COLOR_RESET}"
		echo -e "Server Admin\t\t = ${GREEN}$SERVERADMIN${COLOR_RESET}"
		echo -e "vhost config file\t = ${GREEN}$VHOSTCONF${COLOR_RESET}"
		echo -e "Base Directory\t\t = ${GREEN}$BASEDIR${COLOR_RESET}"
		echo -e "tmp Directory\t\t = ${GREEN}$TMPDIR${COLOR_RESET}"
		echo -e "Username\t\t = ${GREEN}$DBUSER${COLOR_RESET}"
		echo -e "Password\t\t = ${GREEN}$DBPASS${COLOR_RESET}"
		echo -e "Host\t\t\t = ${GREEN}$HOST${COLOR_RESET} \n"
		check_setup
		rm -f $PIDFILE; exit $STATUSDISPLAY
	else
		while getopts "i:d:bslhuw" Option
		do
			case $Option in
				b ) check_setup
					mktmp
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
					mktmp
					update
					break
					;;
				s ) check_setup
					mktmp
					base_setup
					break
					;;
				l ) list_vhosts
					break
					;;
				w ) generateconf
					break
					;;
				h ) usage
					break
					;;
				* ) usage
					break
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

