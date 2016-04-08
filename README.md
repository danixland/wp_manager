wp_manager
====================================

This is a bash script to install and manage WordPress VHosts in a LAMP environment


Description
-----------

I started this project a few years ago, I was dealing with a small webserver where I used to run multiple instances of WordPress to test themes and plugins I was developing and I decided to make the process of installing and mantaining all those different websites a little more *automatic*.
The original script can be found on [github gist](https://gist.github.com/danixland/5237608), it was very simple and just included the possibility to add a new WordPress install in the DocumentRoot and keep it up to date using svn.

This new project has a different goal in mind, I'm trying to create an automated way of effectively mantain different WordPress installs on a local Apache webserver. When I install a new site the script will take care of creating a new VirtualHost, install WordPress and some useful plugins in it and add a new database and user to mysql, then deliver the new site with a precompiled wp-config.php, ready to be activated.
I also want to be able to update all VHosts, list them and delete one or all of them.

As of now, the structure of the script is in place, it's still missing most of the functionalities, but you can see the way it operates.

If you have any ideas you can comment here or you can join the discussion on the [WordPress forums](https://wordpress.org/support/topic/lamp-automated-wordpress-local-environment-suggestions).

License
-------

This code is licensed under the GPL Version 2 license. See the complete license in the root of this repository:

    LICENSE

Reporting an issue or a feature request
---------------------------------------

Issues and feature requests are tracked in the [Github issue tracker](https://github.com/danixland/wp_manager/issues).

When reporting a bug, please be as descriptive and exact as possible.

