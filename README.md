wp_manager 0.8.3
====================================

This is a bash script to install and manage WordPress VHosts in a LAMP environment


Description
-----------

I started this project a few years ago, I was dealing with a small webserver where I used to run multiple instances of WordPress to test themes and plugins I was developing and I decided to make the process of installing and mantaining all those different websites a little more *automatic*.
The original script can be found on [github gist](https://gist.github.com/danixland/5237608), it was very simple and just included the possibility to add a new WordPress install in the DocumentRoot and keep it up to date using svn.

This new project has a different goal in mind, I'm trying to create an automated way of effectively mantain different WordPress installs on a local Apache webserver. When I install a new site the script will take care of creating a new VirtualHost, install WordPress and some useful plugins in it and add a new database and user to mysql, then deliver the new site with a precompiled wp-config.php, ready to be activated.
I also want to be able to update all VHosts, list them and delete one or all of them.

As of now, the structure of the script is in place, its basic functionalities are working, but it needs a lot of testing and some cleanup of the code.

Options
--------

<table>
    <tr>
        <th>Short Option</th>
        <th>Long Option</th>
        <th>Explanation</th>
    </tr>
    <tr>
        <td>-h</td>
        <td>--help</td>
        <td>show the help text and exit.</td>
    </tr>
    <tr>
        <td>-w</td>
        <td>--write-config</td>
        <td>Generate a config file for wp_manager and exit.</td>
    </tr>
    <tr>
        <td>-t</td>
        <td>--test-config</td>
        <td>Perform a check of the current settings and display a brief summary with error reporting.</td>
    </tr>
    <tr>
        <td>-s</td>
        <td>--base-setup</td>
        <td>Create and populate the local cache directory.</td>
    </tr>
    <tr>
        <td>-b</td>
        <td>--base-update</td>
        <td>Update the local cache directory.</td>
    </tr>
    <tr>
        <td>-l</td>
        <td>--list</td>
        <td>Display a list of the VirtualHosts currently set by wp_manager.</td>
    </tr>
    <tr>
        <td>-i [NEW SITE]</td>
        <td>--install-new [NEW SITE]</td>
        <td>Perform a check on "NEW SITE" and then install a new VirtualHost with WordPress and all the plugins already in place.</td>
    </tr>
    <tr>
        <td>-d [SITE NAME]</td>
        <td>--delete [SITE NAME]</td>
        <td>Check if "SITE NAME" is a VirtualHost made by wp_manager and delete all the files, database and the entry in the Apache configuration files.</td>
    </tr>
    <tr>
        <td>-u</td>
        <td>--update</td>
        <td>Update all VirtualHosts generated by wp_manager.</td>
    </tr>
    <tr>
        <td>-k [SITE NAME]</td>
        <td>--backup [SITE NAME]</td>
        <td>Check if "SITE NAME" is a VirtualHost made by wp_manager and create a backup of all the files in the DocumentRoot of the VHost, this will also backup the database and the entry in the Apache configuration files.</td>
    </tr>
</table>

Usage
-------

Using **wp_manager** is very simple, the first step is to generate a config file. By default the script will generate the file in the same directory, but you can change this behaviour by searching for those 2 lines:

    SCRIPTCONFIG=${SCRIPTCONFIG:-"$(dirname $0)/$(basename $0 .sh).conf"}
    #SCRIPTCONFIG=${SCRIPTCONFIG:-"/etc/$(basename $0 .sh).conf"}

and leaving only the second one uncommented to instruct the script to look for a config file inside the /etc directory.
Now to generate the config file issue the command:

	wp_manager -w

and the script will tell you to go and edit it to suit your system configuration.

Once you're done, double check your settings with

    wp_manager -t

and if everything looks fine you can populate your cache directory with all the WordPress goodies that you need, so go ahead and issue:

    wp_manager -s

and after a while the script will tell you that your base directory is ready and up to date.
Usually you'll need to perform this action only the first time and then just update your cache, unless you decide to change the destination of your `$BASEDIR` option, or if you delete your cache directory and need to build it again.

To update your cache directory issue:

	wp_manager -b

and the script will take care of everything. I recommend running this command before installing or updating your WordPress installations, to use the latest codebase available

Now for the fun part, when you want to install a new website, issue

	wp_manager -i <sitename>

and the script will create a new entry in your apache configuration, a new database and install all the WordPress related files and plugins for you, you'll just have to restart apache and update your /etc/hosts file on the clients that will be accessing your server. That's it.

If you need to list the currently available sites you can use

	wp_manager -l

to check on them. In the future I may add a few more info to be displayed.

You'll want to keep your local WordPress installs up to date, so you'll need to run:

	wp_manager -u

and the script will copy the latest modifications to every site that you've setup, without touching files that you may have added like themes or plugins.
It is recommended to run this function after you've updated the base directory.

There will be times when you need to feel safe about what you're doing on your VirtualHost, so running a backup before an important change it's recommended. just run:

    wp_manager -k <sitename>

and wp_manager will tell you that the site has been backed up, the content of the VirtualHost, the database and the entry in the Apache config file is now stored in your $BACKUPDIR.

When you're done with a particular website and you want to delete it, run:

	wp_manager -d <sitename>

you'll be asked to confirm this option and after a few seconds a message will tell you that the site is gone, be careful because there's no turning back and this option will delete **everything** inside that VirtualHost DocRoot.

If you don't remember what an option does or simply how to do something use

	wp_manager -h

and the script will give you a brief help text. Running the script with no options will show the same help text.

More on the Apache setting files
-------

**wp_manager** is able to use either a single file to keep all your vhosts settings or a separate directory with a file for every vhost that you want to setup, it's all well commented in your config file, just remember that by default the separate directory setting will supersede the single file option, so if you want to use the latter option, you'll have to leave the other empty as they are mutually exclusive.

Comments
-------

If you have any ideas you can comment here or you can join the discussion on the [WordPress forums](https://wordpress.org/support/topic/lamp-automated-wordpress-local-environment-suggestions). For my italian speaking friends who are interested I have a discussion going on on [the slacky.eu forum](http://slacky.eu/forum/viewtopic.php?f=20&t=38699) and you're more than welcome to join us.

License
-------

This code is licensed under the GPL Version 2 license. See the complete license in the root of this repository:

    LICENSE

Reporting an issue or a feature request
---------------------------------------

Issues and feature requests are tracked in the [Github issue tracker](https://github.com/danixland/wp_manager/issues).

When reporting a bug, please be as descriptive and exact as possible.

Thank you
