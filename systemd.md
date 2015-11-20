# HOWTO Use systemd for Multiple Instances of SEC

## Preamble

[`systemd`](http://www.freedesktop.org/wiki/Software/systemd/) is a very flexible method of starting and stopping
individual instances of sec on newer operating systems. As most users have multiple files, or multiple rule-sets,
it becomes more important to individually manage each instance rather than reloading the entirety of `sec`.

### Assumptions

1. This document assumes you already have the latest (or a newer) versions of both `sec` and `systemd` installed
via whichever method you choose (`yum`, `apt-get`, tarball).
2. This document outlines file system directories on CentOS 7.  Paths may be different on your preferred flavor.

## Setup

During our journey, we will create the following files, it may be required to create the paths.

### `/etc/systemd/system/sec\@.service`

The `systemd` unit file defines the your service.  You can find more information about the format and structure
of a `systemd` unit file within the references, this document will detail the "non-standard" parts.

    [Unit]
    Description=Simple Event Correlator script to filter log file entries
    After=syslog.target
    
    [Service]
    Type=forking
    TimeoutSec=10
    OOMScoreAdjust=-200
    PIDFile=/var/run/sec.%I.pid
    EnvironmentFile=/etc/sysconfig/sec
    ExecStart=/usr/local/bin/sec --detach --pid=/var/run/sec.%I.pid \
       ${INPUT_%I} --conf=/etc/sec/sec.%I.conf --log=/var/log/sec.%I.log -intevents
    
    [Install]
    WantedBy=multi-user.target

One of the tricks of `systemd` is the ability to fire off multiple instances (instantiated units) based on variables in
the unit file.  Take particular note of the at-sign (@) within the filename. This is very important.  This tells `systemd`
that it will accept instantiated units.

To call an instantiated unit, you will call the service name `sec@foobar` (in this example, more on that later).
`systemd` will substitute any `%I` variable in your unit file with the token after the at-sign.  This way, we can start
`sec@testing`, `sec@development`, `sec@production` without writing 3 unit files.

As each instantiated unit runs, all `%I`'s will be replaced.  In this example, the pid file will be `/var/run/sec.foobar.pid`,
it will look for `/etc/sec/sec.foobar.conf`, and output the log to `/var/log/sec.foobar.log`.

But what if each instance reads a different log from a different directory?  Excellent question.  The `${INPUT_%I}` will
read additional parameters from the `EnvironmentFile` and substitue as appropriately, preventing the need to reload `systemd`
for each change.

As the file stands, there's no input file.  This is where the `EnvironmentFile` comes in.

### `/etc/sysconfig/sec`

The environment file for `systemd` will insert the following based on the variable you passed to the instantiated unit.
This example file sets up the instantiated units ("foobar" and "production") by providing additional details to the unit
file.

    INPUT_foobar=--input=/var/log/foobar.txt
    INPUT_production=--input=/var/log/production.txt

When you want to work with `sec@foobar`, it will insert `--input=/var/log/foobar.txt` into the unit file `ExecStart` line
replacing `${INPUT_%I}` for this instance.

### `/etc/sec/sec.foobar.conf`

This is your standard ruleset file.  No modification for `systemd` is required.  A completely pointless example file is
provided for testing.

    type=Single
    continue=TakeNext
    ptype=RegExp
    pattern=(.*)
    desc=$0
    Action=logonly "Message Found: %s"

## Process Manipulation

Once you create your files (as appropriate if you modified paths within the unit file or decided against "foobar"), you are
ready to get the service installed and start it up.

    root@localhost# systemctl enable sec@foobar.service
    root@localhost# systemctl start sec@foobar

That's it.  There's no step 3!

## Let's Test

First, let's prove the `sec.foobar.txt` file is empty.

    root@localhost# cat /var/log/sec.foobar.txt

Now, let's put something in the `foobar.txt` file that will be picked up by `sec`

    root@localhost# echo "testing" >> /var/log/foobar.txt

Finally, prove that `sec` processed the message.

    root@localhost# cat /var/log/sec.foobar.txt
    Message Found: testing

## Errata

### References

* http://sourceforge.net/p/simple-evcorr/mailman/search/?q=systemd
* https://coreos.com/docs/launching-containers/launching/getting-started-with-systemd/
* http://zero-knowledge.org/post/92/

