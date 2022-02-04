harden.sh
=========

This is a script to harden your Linux installation.

[![asciicast](https://asciinema.org/a/lBaPJhg3KAsp470y9eyLQ2bbA.png)](https://asciinema.org/a/lBaPJhg3KAsp470y9eyLQ2bbA)

Why I made this
---------------

* [Bastille](http://bastille-linux.sourceforge.net/) is obsolete
* Not a member of [CIS](http://www.cisecurity.org/), so no downloading of the ready made scripts
* For learning
* For minimizing the effort needed to tweak fresh installations
  * Also for consistency

What does it do?
----------------

### Common

* Enables [TCP wrappers](https://en.wikipedia.org/wiki/TCP_Wrapper)
* Creates legal banners
* Disable [core dumps](https://en.wikipedia.org/wiki/Core_dump) in `/etc/security/limits.conf`
* [sysctl](https://en.wikipedia.org/wiki/Sysctl) settings hardening
  * IP stack hardening
  * Enables [SAK](https://en.wikipedia.org/wiki/Secure_attention_key) and disables the other [magic SysRq stuff](https://www.kernel.org/doc/Documentation/sysrq.txt)
  * Restricts the use of `dmesg` by regular users
  * Enable [YAMA](https://www.kernel.org/doc/Documentation/security/Yama.txt)
  * For the complete list, see [sysctl.conf.new](https://github.com/pyllyukko/harden.sh/blob/master/newconfs/sysctl.d/sysctl.conf.new)
* Hardens mount options (creates `/etc/fstab.new`)
  * Also, mount [/proc](https://www.kernel.org/doc/Documentation/filesystems/proc.txt) with `hidepid=2`
* Disables the use of certain kernel modules via `modprobe`
  * Disable [Firewire](http://www.hermann-uwe.de/blog/physical-memory-attacks-via-firewire-dma-part-1-overview-and-mitigation)
* Configures shells
  * Creates an option to use [restricted shell](https://en.wikipedia.org/wiki/Restricted_shell) ([rbash](https://www.gnu.org/software/bash/manual/html_node/The-Restricted-Shell.html))
    * Also sets it as default for new users
  * Restricts the number of available shells (`/etc/shells`)
* Configures basic auditing based on [stig.rules](https://fedorahosted.org/audit/browser/trunk/contrib/stig.rules) if audit is installed
  * NOTE: non-PAM systems (namely Slackware) don't set the `loginuid` properly, so some of the rules don't work when they have `-F auid!=4294967295`
* Enables system accounting ([sysstat][10])
  * Sets it's log retention to 99999 days (the logs are really small, so it doesn't eat up disk space)
* Configures password policies
  * Maximum age for password
  * Minimum age for password
  * Password warn age
  * Does this for existing users also
  * Note: password strength should be enforced with applicable PAM module (such as [pam_passwdqc](http://www.openwall.com/passwdqc/) or `pam_pwquality`)
* Reduce the amount of trusted [CAs](https://en.wikipedia.org/wiki/Certificate_authority)
  * Doesn't work in CentOS/RHEL
* Create a strict `securetty`
* Sets default [umask](https://en.wikipedia.org/wiki/Umask) to a more stricter `077`
* Sets console session timeout via `$TMOUT` (Bash)
* PAM:
  * Configures `/etc/security/namespace.conf`
  * Configures `/etc/security/access.conf`
  * Configures `/etc/security/pwquality.conf` if available
  * Require [pam_wheel](http://linux-pam.org/Linux-PAM-html/sag-pam_wheel.html) in `/etc/pam.d/su`
  * Creates a secure [/etc/pam.d/other](http://linux-pam.org/Linux-PAM-html/sag-security-issues-other.html)
* Disables unnecessary systemd services
* Configures `sshd_config`
* Display managers:
  * Disables user lists in GDM3 & LightDM
  * Disables guest sessions in LightDM

#### User accounts

* Configures failure limits (`faillog`)
* Creates `/etc/ftpusers`
* Restricts the use of `cron` and `at`
* Properly locks down system accounts (0 - `SYS_UID_MAX` && !`root`)
  * Lock the user's password
  * Sets shell to `nologin`
  * Expire the account
  * Adds the accounts to [/etc/ftpusers](http://linux.die.net/man/5/ftpusers)
* Sets strict permissions to users home directories
* Configures the default password inactivity period

### Debian specific

* Enables AppArmor
* Sets the [authorized\_default](https://www.kernel.org/doc/Documentation/usb/authorization.txt) to USB devices via `rc.local`
* APT:
  * Configures APT not to install suggested packages
  * Configure `SUITE` in `debsecan` (if installed)

#### PAM

Creates bunch of `pam-config`s that are toggleable with `pam-auth-update`:

| PAM module                                                                                   | Type           | Description                                                                             |
| -------------------------------------------------------------------------------------------- | -------------- | --------------------------------------------------------------------------------------- |
| [pam\_wheel](http://www.linux-pam.org/Linux-PAM-html/sag-pam_wheel.html)[<sup>1</sup>](#fn1) | auth           | Require `wheel` group membership (`su`)                                                 |
| [pam\_succeed\_if](http://www.linux-pam.org/Linux-PAM-html/sag-pam_succeed_if.html)          | auth & account | Require UID >= 1000 && UID <= 60000 (or 0 & `login`)                                    |
| [pam\_unix](http://www.linux-pam.org/Linux-PAM-html/sag-pam_unix.html)[<sup>1</sup>](#fn1)   | auth           | Remove `nullok`                                                                         |
| [pam\_faildelay](http://www.linux-pam.org/Linux-PAM-html/sag-pam_faildelay.html)             | auth           | Delay on authentication failure                                                         |
| [pam\_tally2](http://www.linux-pam.org/Linux-PAM-html/sag-pam_tally2.html)                   | auth & account | Deter brute-force attacks                                                               |
| [pam\_access](http://linux-pam.org/Linux-PAM-html/sag-pam_access.html)                       | account        | Use login ACL (`/etc/security/access.conf`)                                             |
| [pam\_time](http://www.linux-pam.org/Linux-PAM-html/sag-pam_time.html)                       | account        | `/etc/security/time.conf`                                                               |
| [pam\_lastlog](http://www.linux-pam.org/Linux-PAM-html/sag-pam_lastlog.html)                 | account        | Lock out inactive users (no login in 90 days)                                           |
| [pam\_namespace](http://www.linux-pam.org/Linux-PAM-html/sag-pam_namespace.html)             | session        | Polyinstantiated temp directories                                                       |
| [pam\_umask](http://www.linux-pam.org/Linux-PAM-html/sag-pam_umask.html)                     | session        | Set file mode creation mask                                                             |
| [pam\_lastlog](http://www.linux-pam.org/Linux-PAM-html/sag-pam_lastlog.html)                 | session        | Display info about last login and update the lastlog and wtmp files[<sup>2</sup>](#fn2) |
| [pam\_pwhistory](http://www.linux-pam.org/Linux-PAM-html/sag-pam_pwhistory.html)             | password       | Limit password reuse                                                                    |

1. <span id="fn1"/>Not a `pam-config`, but a modification to existing `/etc/pam.d/` files
2. <span id="fn2"/>For all login methods and not just the console login

### CentOS/RHEL specific

* PAM configuration with `authconfig`:
  * Enables `pam_faillock`
  * Configures `pwquality`

### Slackware specific

See [SLACKWARE.md](SLACKWARE.md).

### Additional features

* SSH moduli creation
* Some hardening steps utilize [Lynis](https://cisofy.com/lynis/) to verify themselves (to be improved/extended over time)

#### PGP

The `import_pgp_keys()` function imports a bunch of PGP keys to your `trustedkeys.gpg` keyring, so you can verify downloaded files/packages with [gpgv](http://www.gnupg.org/documentation/manuals/gnupg/gpgv.html). The keys that are imported are listed in the `PGP_URLS[]` and `PGP_KEYS[]` arrays.

Notes
-----

* Rebooting the system after running this is highly recommended, since many startup scripts are modified
* The script is quite verbose, so you might want to record it with `script`
* It is best to run this script on a fresh installation for best results

### Other security software

#### Antivirus

I think it's justified and recommended to run an antivirus software on all of your Linux servers. This is because, even though the server's role would not be something like a file sharing server or a mail server, a proper antivirus is able to detect much more than these "traditional" malwares. I'm talking about rootkits, exploits, [PHP shells](https://en.wikipedia.org/wiki/Backdoor_Shell) and the like. Something that a malicious user might be holding at their home dirs or maybe some PHP shell was dropped through a vulnerable web application. If you would get an early warning from an antivirus software, it just might save you on that one occasion :)

So consider getting [ClamAV](https://www.clamav.net/).

### Daily checks and reports

At least the following tools support daily checks and reporting via e-mail out-of-the-box:

* Tiger (via `tigercron`)
    * Can also run `chkrootkit` & AIDE
* Logwatch
* `rkhunter --cron`
    * Read "How can I automatically run Rootkit Hunter every day?" in the FAQ
    * Debian has `/etc/cron.{daily,weekly}/rkhunter` for this
* `sudo` (well not daily, but by event)

Debian specific:

| Tool                | Cron job                                 | Configuration                             |
| ------------------- | ---------------------------------------- | ----------------------------------------- |
| debsecan            | /etc/cron.d/debsecan                     | /etc/default/debsecan                     |
| AIDE                | /etc/cron.daily/aide                     | /etc/default/aide                         |
| unattended-upgrades | N/A - systemd service                    | /etc/apt/apt.conf.d/50unattended-upgrades |
| logcheck            | /etc/cron.d/logcheck                     | /etc/logcheck/                            |
| john                | /etc/cron.d/john                         | `JOHN_OPTIONS` & /etc/john/john-mail.conf |
| debsums             | /etc/cron.{daily,weekly,monthly}/debsums | /etc/default/debsums                      |
| chkrootkit          | /etc/cron.daily/chkrootkit               | /etc/chkrootkit.conf                      |
| checksecurity       | /etc/cron.{daily,weekly}/checksecurity   | /etc/checksecurity.conf                   |

Post-hardening checklist
------------------------

After running the hardening script, the following actions still need to be performed manually:

- [ ] Set LILO/GRUB password
  - [ ] Update LILO/GRUB with `lilo` || `update-grub`
- Install at least the following additional software:
  - [ ] [audit](https://people.redhat.com/sgrubb/audit/) (and run `harden.sh -S` afterwards)
  - [ ] [Aide](http://aide.sourceforge.net/)
  - [ ] ClamAV
  - [ ] arpwatch
  - [ ] rngd (if you have [HRNG](https://en.wikipedia.org/wiki/Hardware_random_number_generator))
- [ ] Make sure NTP is running
- [ ] Configure remote log host
- [ ] Add legit users to:
  - `/etc/porttime`
  - To the `users` group

References
----------

### Hardening guides

Some of these documents are quite old, but most of the stuff still applies.

* [CIS Slackware Linux 10.2 Benchmark v1.1.0][1]
* [Slackware System Hardening][2] by Jeffrey Denton
* [CIS Debian Linux Benchmark](https://www.cisecurity.org/benchmark/debian_linux/)
* [CIS CentOS Linux 7 Benchmark](https://www.cisecurity.org/benchmark/centos_linux/)
* [SlackDocs: Security HOWTOs](http://docs.slackware.com/howtos:security:start)
* [Alien's Wiki: Security issues](http://alien.slackbook.org/dokuwiki/doku.php?id=linux:admin#security_issues)
* [SlackWiki: Basic Security Fixes](http://slackwiki.com/Basic_Security_Fixes)
* [Wikipedia: Fork bomb Prevention](https://en.wikipedia.org/wiki/Fork_bomb#Prevention)

### Other docs

* [Linux Standard Base Core Specification 4.1](http://refspecs.linuxfoundation.org/LSB_4.1.0/LSB-Core-generic/LSB-Core-generic/book1.html)
  * [Chapter 21. Users & Groups](http://refspecs.linuxfoundation.org/LSB_4.1.0/LSB-Core-generic/LSB-Core-generic/usernames.html)
* [Filesystem Hierarchy Standard 2.3](http://refspecs.linuxfoundation.org/FHS_2.3/fhs-2.3.html)
* <https://iase.disa.mil/stigs/os/unix-linux/Pages/index.aspx>
* [PAM Mastery book](https://www.tiltedwindmillpress.com/?product=pam) by [Michael W Lucas](https://www.michaelwlucas.com/)
* [The Linux-PAM System Administrators' Guide](http://linux-pam.org/Linux-PAM-html/Linux-PAM_SAG.html)
* [Sudo Mastery, 2nd Edition](https://www.tiltedwindmillpress.com/product/sudo-mastery-2nd-edition/)
* [Linux Firewalls](https://nostarch.com/firewalls.htm)
* [Secure Secure Shell](https://stribika.github.io/2015/01/04/secure-secure-shell.html)
* [Securing Debian Manual](https://www.debian.org/doc/manuals/securing-debian-manual/index.en.html)

[1]: http://benchmarks.cisecurity.org/downloads/browse/index.cfm?category=benchmarks.os.linux.slackware
[2]: http://dentonj.freeshell.org/system-hardening-10.2.txt
[10]: http://sebastien.godard.pagesperso-orange.fr/
