ebs-monitor
===========

This project is aimed at shutting down services and databases based on disk access.

If a network disk - one like Amazon's EBS volumes - goes down, the IO call gets stuck in the Linux kernel. The service or database will still be listening on the port, clients will still connect, but the requests will all time out over and over again.

How it works
------------

There is a single process, the monitor, that is not dependent on disk access. There will be one or many reporter processes that report to the monitor process.

The reporters will touch a file in a directory once every so often and then send a healthy heartbeat to the monitor. The message also contains which TCP ports should be shut down should the heartbeats stop coming. Upon a disk failure, the touch will either hang indefinitely or fail. In either case, the heartbeat will be skipped.

The monitor listens for all the heartbeats. All new reporter processes will be registered automatically with the monitor. After a configurable amount of time passes without a heartbeat from any of the registered reporters, the monitor will insert a new iptables rule to stop all remote traffic to the associated tcp ports associated with that reporter. Once the reporter comes back online, the iptables rule will be removed, and traffic will resume to the tcp ports.

The changes to iptables affect only the filter table. Only rules related to the disk monitor scripts will be affected. Other rules will not be added, removed, reordered, or messed with in any way.

Usage
-----

Both the reporter and the monitor script take a fifo parameter. As long as that is the same, everything should work perfectly.

Here is an example that could be run on a MySQL server.

    ./disk-monitor.rb --daemonize --fifo=/var/run/disk-monitor.fifo

    ./disk-reporter.rb --daemonize --pidfile=/var/run/mysql-disk-reporter.pid --logfile=/var/log/mysql-disk-reporter.log --fifo=/var/run/disk-monitor.fifo --monitor=/var/lib/mysql --ports=3306

Here is an example that could be run on an Apache server.

    ./disk-monitor.rb --daemonize --fifo=/var/run/disk-monitor.fifo

    ./disk-reporter.rb --daemonize --pidfile=/var/run/apache-disk-reporter.pid --logfile=/var/log/apache-disk-reporter.log --fifo=/var/run/disk-monitor.fifo --monitor=/var/www/html --ports=80,443


