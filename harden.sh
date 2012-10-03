#!/bin/bash
################################################################################
# file:		harden.sh
# created:	25-09-2010
# modified:	2012 Oct 03
#
# TODO:
#   - guides to read:
#     - http://www.nsa.gov/ia/_files/os/redhat/rhel5-guide-i731.pdf
#     - http://www.auscert.org.au/5816 "UNIX and Linux Security Checklist v3.0"
#     - http://www.puschitz.com/SecuringLinux.shtml
#     - http://linuxgazette.net/issue91/kruk.html
#     - https://www.sans.org/score/unixchecklist.php
#     - maybe some tips from http://www.debian.org/doc/user-manuals#securing
#   - logrotate
#     -> done?
#   - create .preharden backups (only once?)
#   - create a function/script that reads file permissions from nessus' audit
#     files?
#   - USERDEL_CMD from LOGIN.DEFS(5)
#   - is /var/empty suitable as a home dir for some system accounts?
#   - X hardening
#   * generic/fast/simple hardening for unsupported systems ("quick harden")
#     * sysctl.conf
#     * TCP wrappers
#     - umask in /etc/profile & /etc/limits
#     * create suauth
#     * ftpusers
#   - immutable flags (chattr)
#   - some variables to read only?
#     - from rbash: SHELL, PATH, ENV, or BASH_ENV
#     - from system-hardening-10.2.txt: HISTCONTROL HISTFILE HISTFILESIZE HISTIGNORE HISTNAME HISTSIZE LESSSECURE LOGNAME USER
#   - replace all UIDs with UID_MIN, UID_MAX, SYS_UID_MIN...
#   * inetd services
#   - how do we reset faillogs after successful login?
#   - add install_additional_software()
#   - Shadow suite S/Key support (/usr/doc/shadow-4.1.4.3/README)
#   - separate sudo into it's own patch!!!
#   - ssh_keyscan.sh
#   - http://www.gnupg.org/documentation/manuals/gnupg/addgnupghome.html#addgnupghome
#   - /usr/bin/ch{mod,own} -> from PATH. since Debian has them under /bin
#
# NOTES:
#   - i designed this so it can be run multiple times (with maybe the exception of disabling services)
#   - i tried to write as many comments that i've could about what this script does and also mark the reason.
#
# what i've used for reference:
#   - CIS Slackware Linux Benchmark v1.1
#   - Slackware System Hardening (http://dentonj.freeshell.org/system-hardening-10.2.txt) by Jeffrey Denton
#   - whatever tiger "The Unix security audit and intrusion detection tool" have told me=)
#   - Nessus' audit files
#
# why i made this:
#   - no bastille for slackware
#   - not a member of CIS, so no downloading of the ready made scripts=(
#   - for learning
#   - for minimizing the effort needed to tweak fresh installations
#
# changelog:
#   - 29.9.2012: started working against slackware 14.0
#
# what does it do:
#
#   - harden user accounts
#     - properly locks down system accounts
#     - sets restrictions for normal users
#       - sets the maximum number of processes available to a single user (ulimit -u)
#       - sets the maximum size of core files created (ulimit -c)
#       - sets a session timeout (TMOUT) in certain conditions
#       - sets a maximum number of failed login attempts (faillog)
#     - restricts the number of available shells
#       - also removes "unnecessary" shells
#     - creates an option to use restricted bash (rbash)
#   - removes unnecessary services
#     - xinetd
#     - goes through /etc/rc.d/rc.* and disables plenty of those
#   - enables additional security related services
#     - system accounting
#     - firewall (rc.firewall)
#
################################################################################
if [ ${BASH_VERSINFO[0]} -ne 4 ]
then
  echo -e "error: bash version != 4, this script might not work properly!" 1>&2
  echo    "       you can bypass this check by commenting out lines $[${LINENO}-2]-$[${LINENO}+2]." 1>&2
  exit 1
fi
shopt -s extglob
set -u
export PATH="/usr/sbin:/sbin:/usr/bin:/bin"
for PROGRAM in \
  awk \
  cat \
  cp \
  faillog \
  id \
  usermod \
  grpck \
  chmod \
  chown \
  date \
  gawk \
  grep \
  ln \
  mkdir \
  mv \
  rm \
  sed \
  shred \
  stat
do
  if ! hash "${PROGRAM}" 2>/dev/null
  then
    printf "error: command not found in PATH: %s\n" "${PROGRAM}" >&2
    exit 1
  fi
done
unset PROGRAM
# the rc.modules* should match at least the following:
#   - rc.modules.local
#   - rc.modules-2.6.33.4
#   - rc.modules-2.6.33.4-smp
declare -r SA_RC="/etc/rc.d/rc.sysstat"
SERVICES_WHITELIST=(
  /etc/rc.d/rc.0
  /etc/rc.d/rc.4
  /etc/rc.d/rc.6
  /etc/rc.d/rc.K
  /etc/rc.d/rc.M
  /etc/rc.d/rc.S
  /etc/rc.d/rc.acpid
  /etc/rc.d/rc.firewall
  /etc/rc.d/rc.font
  /etc/rc.d/rc.inet1
  /etc/rc.d/rc.inet2
  /etc/rc.d/rc.keymap
  /etc/rc.d/rc.local
  /etc/rc.d/rc.local_shutdown
  /etc/rc.d/rc.modules
  /etc/rc.d/rc.modules-+([0-9.])?(-smp)
  /etc/rc.d/rc.modules.local
  /etc/rc.d/rc.netdevice
  /etc/rc.d/rc.sshd
  /etc/rc.d/rc.syslog
  "${SA_RC}"
  /etc/rc.d/rc.udev
)
#declare -ra LOG_FILES=(
#  btmp
#  cron*
#  debug*
#  dmesg
#  faillog
#  lastlog
#  maillog*
#  messages*
#  secure*
#  spooler*
#  syslog*
#  wtmp
#  xferlog
#)
declare -r GPG_KEYRING="trustedkeys.gpg"
#declare -r ETC_PATCH_VERSION="13.37-20110429-1"
#declare -r ETC_PATCH_VERSION="13.37-20110801"
#declare -r ETC_PATCH_VERSION="13.37-20120413"
declare -r ETC_PATCH_VERSION="14.0-20120929"
declare -r ETC_PATCH_FILE="harden_etc-${ETC_PATCH_VERSION}.patch"
#declare -r APACHE_PATCH_VERSION="2.2.17-20110507"
declare -r APACHE_PATCH_VERSION="2.4.3-20120929-1"
declare -r APACHE_PATCH_FILE="harden_apache-${APACHE_PATCH_VERSION}.patch"
declare -r APACHE_PATCH_MODULES_X86_64_FILE="harden_apache-2.2.17-modules-x86_64-20110330.patch"
declare -r APACHE_PATCH_MODULES_X86_FILE="harden_apache-2.2.17-modules-x86-20110424.patch"
#declare -r SSH_PATCH_FILE="ssh_harden-20110517-3.patch"
#declare -r SSH_PATCH_FILE="ssh_harden-20110616.patch"
#declare -r SSH_PATCH_FILE="ssh_harden-20120413.patch"
declare -r SSH_PATCH_FILE="ssh_harden-20120929-1.patch"
declare -r SENDMAIL_PATCH_FILE="sendmail_harden-20110918-1.patch"
declare -r SLACKWARE_VERSION=`sed 's/^.*[[:space:]]\([0-9]\+\.[0-9]\+\).*$/\1/' /etc/slackware-version 2>/dev/null`
# these are not declared as integers cause then the ${ ... :-DEFAULT } syntax won't work(?!)
declare -r UID_MIN=`awk '/^UID_MIN/{print$2}' /etc/login.defs 2>/dev/null`
declare -r UID_MAX=`awk '/^UID_MAX/{print$2}' /etc/login.defs 2>/dev/null`
declare -r SYS_UID_MAX=`awk '/^SYS_UID_MAX/{print$2}' /etc/login.defs 2>/dev/null`
declare -r WWWROOT="/var/www"
declare -i ETC_CHANGED=0
declare -r SENDMAIL_CF_DIR="/usr/share/sendmail/cf/cf"
declare -r SENDMAIL_CONF_PREFIX="sendmail-slackware"
declare -r RBINDIR="/usr/local/rbin"
declare -r INETDCONF="/etc/inetd.conf"

# NOLOGIN(8): "It is intended as a replacement shell field for accounts that have been disabled."
# Slackware default location:
if [ -x /sbin/nologin ]
then
  DENY_SHELL="/sbin/nologin"
# Debian default location:
elif [ -x /usr/sbin/nologin ]
then
  DENY_SHELL="/usr/sbin/nologin"
else
  echo "warning: can't find nologin!" 1>&2
  DENY_SHELL=
fi
# man FAILLOG(8)
declare -i FAILURE_LIMIT=10
declare -r CERTS_DIR="/etc/ssl/certs"

# from CIS 2.1 Disable Standard Services
declare -a INETD_SERVICES=(echo discard daytime chargen time ftp telnet comsat shell login exec talk ntalk klogin eklogin kshell krbupdate kpasswd pop imap uucp tftp bootps finger systat netstat auth netbios swat rstatd rusersd walld)

# ...plus some extras
INETD_SERVICES+=(pop3 imap2 netbios-ssn netbios-ns)

# more info about these PGP keys:
#   - http://www.slackbuilds.org/faq/#asc
#   - http://nmap.org/book/install.html#inst-integrity
#   - http://www.cipherdyne.org/contact.html
#   - http://www.openwall.com/signatures/ (295029F1)
#   - http://www.nongnu.org/tiger/key.html & http://savannah.nongnu.org/users/jfs
#   - http://www.atagar.com/pgp.php
#   - http://wiki.centos.org/FAQ/CentOS5#head-3a83196c7a97a7990ca646cbd135fd67198fe812
#     (centos key here might seem odd, but i want to be able to verify ISO
#      images i've downloaded)
#   - https://kismetwireless.net/download.shtml#gpg
#   - aide:
#     - http://aide.sourceforge.net/
#     - http://sourceforge.net/projects/aide/files/PGP%20key/
#   - http://wiki.clamav.net/bin/view/Main/FAQ#How_do_I_verify_the_integrity_of
#   - http://www.wangafu.net/~nickm/ 8D29319A - Nick Mathewson (libevent)
declare -ra PGP_URLS=(
  "http://www.slackware.com/gpg-key"
  "http://slackbuilds.org/GPG-KEY"
  "http://nmap.org/data/nmap_gpgkeys.txt"
  "http://www.cipherdyne.org/signing_key"
  "http://www.openwall.com/signatures/openwall-signatures.asc"
  "http://savannah.nongnu.org/people/viewgpg.php?user_id=7475"
  "http://www.atagar.com/resources/damianJohnson.asc"
  "http://mirror.centos.org/centos/RPM-GPG-KEY-CentOS-5"
  "https://www.kismetwireless.net/dragorn.gpg"
  "http://sourceforge.net/projects/aide/files/PGP%20key/aide-2010_0xCBF11FCD.asc/download"
  "http://www.clamav.net/gpg/tkojm.gpg"
  "http://www.wangafu.net/~nickm/public_key.asc"
)

# other PGP keys:
#   - CEA0A321 - James Lee <egypt@metasploit.com>
#                (metasploit project signing key)
#   - 61355B9E - HD Moore
#   - 28988BF5 - Roger from torproject
#                https://www.torproject.org/docs/verifying-signatures.html.en
#   - 19F78451 - -- || --
#   - 6980F8B0 - Breno Silva (ModSecurity)
#   - D679F6CF - Karl Berry <karl@freefriends.org> (gawk)
#   - BF2EA563 - Fabian Keil, lead developer of privoxy
#   - 63FEE659 - Erinn Clark (Tor Browser Bundles)
#                https://www.torproject.org/docs/signing-keys.html.en
#   - 6294BE9B - http://www.debian.org/CD/verify
#   - 9624FCD2 - Ryan Barnett (OWASP Core Rule Set Project Leader) <rbarnett@trustwave.com>
#                https://www.owasp.org/index.php/Category:OWASP_ModSecurity_Core_Rule_Set_Project#Download
#   - 4245D46A - Bradley Spengler (spender) (grsecurity)
#                https://grsecurity.net/contact.php
#   - 6092693E - https://www.kernel.org/signature.html
#   - DDC6C0AD - https://www.torproject.org/torbutton/
#   - C52175E2 - http://releases.mozilla.org/pub/mozilla.org/firefox/releases/3.6.28/KEY
#   - 1FC730C1 - Bitcoin
declare -ra PGP_KEYS=(
  "CEA0A321"
  "61355B9E"
  "28988BF5"
  "19F78451"
  "6980F8B0"
  "D679F6CF"
  "BF2EA563"
  "63FEE659"
  "6294BE9B"
  "9624FCD2"
  "4245D46A"
  "6092693E"
  "DDC6C0AD"
  "C52175E2"
  "1FC730C1"
)
# if there is a recommended/suggested server for a key
declare -rA PGP_KEYSERVERS=(
  ["28988BF5"]="keys.gnupg.net"
)
declare -r DEFAULT_KEYSERVER="keys.gnupg.net"
declare -r ARCH=`/bin/uname -m`
################################################################################
function chattr_files_NOT_IN_USE() {
  # NOTE: not in use, at least not yet.

  local i

  # CIS SN.4 Additional LILO Security
  chattr +i /etc/lilo.conf

  # system-hardening-10.2.txt: Filesystem
  for i in `ls /etc/rc.d`
  do
    chattr +i /etc/rc.d/$i
  done
  for i in `ls /etc/httpd`
  do
    chattr +i /etc/httpd/$i
  done
  for i in `ls /etc/mail`
  do
    chattr +i /etc/mail/$i
  done

  find / -type f \( -perm -4000 -o -perm -2000 \) -exec chattr +i {} \;

  chattr +i /etc/at.deny
  chattr +i /etc/exports
  chattr +i /etc/ftpusers
  chattr +i /etc/host.conf
  chattr +i /etc/hosts
  chattr +i /etc/hosts.allow
  chattr +i /etc/hosts.deny
  chattr +i /etc/hosts.equiv
  chattr +i /etc/hosts.lpd
  chattr +i "${INETDCONF}"
  chattr +i /etc/inittab
  #chattr +i /etc/lilo.conf
  chattr +i /etc/login.access
  chattr +i /etc/login.defs
  chattr +i /etc/named.conf
  chattr +i /etc/porttime
  chattr +i /etc/profile
  chattr +i /etc/protocols
  chattr +i /etc/securetty
  chattr +i /etc/services
  chattr +i /etc/suauth
  #chattr +i /home/dentonj/.forward
  #chattr +i /home/dentonj/.netrc
  #chattr +i /home/dentonj/.rhosts
  #chattr +i /home/dentonj/.shosts
  chmod go-rwx /usr/bin/chattr /usr/bin/lsattr

  return
} # chattr_files()
################################################################################
function install_additional_software_NOT_IN_USE() {
  # TODO:
  #   - under construction
  #   - what to do with the "(P)roceed or (Q)uit?:" prompt?
  if [ -x /usr/sbin/sbopkg ]
  then
    # sync the repos
    /usr/sbin/sbopkg -r || {
      echo "${FUNCNAME}(): error: error syncing repos!" 1>&2
      return 1
    }
  else
    echo "${FUNCNAME}(): error: sbopkg not found!" 1>&2
    return 1
  fi
  return
} # install_additional_software()
################################################################################
function disable_inetd_services() {
  # CIS 2.1 Disable Standard Services
  local SERVICE

  if [ ! -f "${INETDCONF}" ]
  then
    echo "${FUNCNAME}(): error: inetd conf file not found!" 1>&2
    return 0
  fi

  echo "${FUNCNAME}(): disabling inetd services"

  if [ ! -f "${INETDCONF}.original" ]
  then
    cp -v "${INETDCONF}" "${INETDCONF}.original"
  fi

  for SERVICE in ${INETD_SERVICES[*]}
  do
    sed -i 's/^\('"${SERVICE}"'\)/\#\1/' "${INETDCONF}"
  done

  return
} # disable_inetd_services()
################################################################################
function create_environment_for_restricted_shell () {
  # TODO: NOT IN USE. UNDER CONSTRUCTION.
  local PRG

  if [ ! -d "${RBINDIR}" ]
  then
    mkdir -pv "${RBINDIR}"
  fi
  chown -c root:root "${RBINDIR}"
  chmod -c 755 "${RBINDIR}"

  #rm -v "${RBINDIR}/"*

  pushd "${RBINDIR}" || return 1

  for PRG in passwd id ls
  do
    ln -s /usr/bin/${PRG}
  done

  popd

  return
} # create_environment_for_restricted_shell()
################################################################################
function import_pgp_keys() {
  local URL
  local KEYSERVER
  local PGP_KEY

  echo "${FUNCNAME}(): importing PGP keys"
  # keys with URL
  for URL in ${PGP_URLS[*]}
  do
    # after importing these keys, we can verify slackware packages with gpgv
    /usr/bin/wget --tries=5 "${URL}" --output-document=- | gpg --keyring "${GPG_KEYRING}" --no-default-keyring --import -
  done
  # keys with key ID
  # set is to avoid "./harden.sh: line 427: PGP_KEYSERVERS[${PGP_KEY}]: unbound variable"
  set +u
  for PGP_KEY in ${PGP_KEYS[*]}
  do
    if [ -n "${PGP_KEYSERVERS[${PGP_KEY}]}" ]
    then
      KEYSERVER="${PGP_KEYSERVERS[${PGP_KEY}]}"
    else
      KEYSERVER="${DEFAULT_KEYSERVER}"
    fi
    /usr/bin/gpg --keyserver "hkp://${KEYSERVER}" --keyring "${GPG_KEYRING}" --no-default-keyring --recv-keys "${PGP_KEY}"
  done
  set -u
  return 0
} # import_pgp_keys()
################################################################################
function user_accounts() {
  # NOTE: http://refspecs.freestandards.org/LSB_4.1.0/LSB-Core-generic/LSB-Core-generic/usernames.html
  #
  # NOTE: http://www.redhat.com/archives/nahant-list/2007-March/msg00163.html (good thread about halt & shutdown accounts)
  #
  # TODO: for loop through SYS_UID_MIN - SYS_UID_MAX
  # TODO: groups (or are they even necessary?)
  # TODO: it still might be too dangerous to just start removing anything. reconsider this.

  local -i GRPCK_RET
  local MyUID
  local NAME
  local USERID
  local USER_HOME_DIR

  if [ ! -x "${DENY_SHELL}" ]
  then
    echo "${FUNCNAME}(): error: invalid \$DENY_SHELL!" 1>&2
    return 1
  fi

  #echo "${FUNCNAME}(): removing unnecessary user accounts"

  # system-hardening-10.2.txt:
  #
  # remove user account 'gdm'
  #   - suggested in system-hardening-10.2.txt
  #   - gnome was dropped from slackware in v10.2
  #   - from ftp://ftp.slackware.com/pub/slackware/slackware-10.2/ChangeLog.txt:
  #     "gnome/*:  Removed from -current"...
  #
  # operator:
  #   - according to LSB Core Specification 4.1 (21.2. User & Group Names, Table 21-2)
  #     the user 'operator' is optional
  #
  # halt, shutdown & sync:
  #   "The accounts "halt" and "shutdown" don't work
  #    by default.  The account "sync" isn't needed."
  # NOTE: 25.9.2012: disabled, so we don't get any unowned files.
  #for USERID in adm gdm operator halt shutdown sync
  #do
  #  /usr/bin/crontab -d -u	"${USERID}"
  #  /usr/sbin/userdel		"${USERID}"
  #done

  # CUSTOM

  # result from /usr/sbin/pwck -r
  #
  # NOTE: if the packages are added on a later date, the user accounts
  #       will probably be missing.
  # WARNING! this might lead to unowned files and directories if some of the
  #          packages are installed afterwards.
  # NOTE: user lp shouldn't be removed, few devices are owned by this account
  #
  # TODO:
  #   - these users might still have some files/directories on the system
  #     we should check that before we remove these users, so we don't
  #     end up with unowned files/directories
  #
  # the home directories exist if the packages are installed:
  # drwxrwxr-x uucp/uucp         0 1993-08-12 21:18 var/spool/uucppublic/
  # drwxr-xr-x root/root         0 2010-05-15 13:10 usr/games/
  # drwxr-xr-x root/root         0 2011-04-04 23:07 home/ftp/
  # drwxrwx--- smmsp/smmsp       0 2002-02-13 19:21 var/spool/clientmqueue/
  # drwxr-x--- mysql/mysql       0 2011-04-05 17:33 var/lib/mysql/
  # drwxr-xr-x root/root         0 2010-12-23 18:46 var/run/dbus/
  # drwxr-xr-x haldaemon/haldaemon 0 2010-11-16 16:55 var/run/hald/
  #
  # NOTE: 25.9.2012: disabled, so we don't get any unowned files.
  #for NAME in uucp games ftp smmsp mysql messagebus haldaemon
  #do
  #  USER_HOME_DIR=$( awk -F':' '$1=="'"${NAME}"'"{print$6}' /etc/passwd )

  #  # this could mean the account is already removed...
  #  if [ -z "${USER_HOME_DIR}" ]
  #  then
  #    echo "${FUNCNAME}(): INFO: user '${NAME}' might have already been removed"
  #    continue
  #  fi

  #  if [ ! -d "${USER_HOME_DIR}" ]
  #  then
  #    echo "${FUNCNAME}(): DEBUG: user '${NAME}': directory '${USER_HOME_DIR}' does not exist"
  #    /usr/bin/crontab -d -u	"${NAME}"
  #    /usr/sbin/userdel		"${NAME}"
  #    /usr/sbin/groupdel	"${NAME}"
  #  fi
  #done

  # on slackware 13.37 the user news has /usr/lib/news as home directory which
  # does not exist. we use an easy way to determine wether the news clients are
  # installed.
  #
  # NOTE: 25.9.2012: disabled, so we don't get any unowned files.
  #if [ ! -d "/usr/lib/nn" -a ! -d "/var/spool/slrnpull" ]
  #then
  #  /usr/bin/crontab -d -u	news
  #  /usr/sbin/userdel		news
  #  /usr/sbin/groupdel		news
  #fi

  echo "${FUNCNAME}(): modifying/hardening current user accounts"

  # CIS 8.1 Block System Accounts (modified)
  # CIS 3.4 Disable Standard Boot Services (modified) (the user accounts part)
  #
  # NOTE: according to CIS (3.13 Only Enable SQL Server Processes If Absolutely Necessary & 8.1 Block System Accounts)
  #       mysql user account needs to have bash as it's shell.
  #
  # NOTE:
  #   - this should be run periodically
  #   - 29.8.2012: added expire as suggested in passwd(1)
  #
  # TODO: find out the details about mysql's shell!!
  for NAME in `cut -d: -f1 /etc/passwd`
  do
    MyUID=`id -u ${NAME}`
    if [ \
      ${MyUID} -le ${SYS_UID_MAX:-999} -a \
      ${NAME} != 'root' ]
    then
      /usr/sbin/usermod -e 1970-01-02 -L -s "${DENY_SHELL}" "${NAME}"
    fi
  done

  # this satisfies CIS Apache Web Server 2.2.0 Benchmark 1.6 "Creating the Apache User and Group Accounts."
  # from Nessus CIS_Apache_v2_1.audit
  # NOTE: 25.9.2012: disabled, for consistency's sake.
  #/usr/sbin/usermod -d /dev/null -s "${DENY_SHELL}" apache

  # currently (13.1) slackware has this in passwd:
  #   lp:x:4:7:lp:/var/spool/lpd:/bin/false
  # lprng had this dir back in 11.0, even then it was in pasture/
  #   drwx------ lp/lp             0 2006-02-03 04:55 var/spool/lpd/
  if [ ! -d /var/spool/lpd -a -d /var/spool/cups ]
  then
    /usr/sbin/usermod -d /var/spool/cups lp
  fi

  # from README.privsep
  # another less tiger warning (pass016w)
  /usr/sbin/usermod -c 'sshd privsep' -d /var/empty sshd

  user_home_directories_permissions

  # CUSTOM

  # this should create the missing entries to /etc/gshadow
  if [ -x /usr/sbin/grpck ]
  then
    /usr/sbin/grpck -r
    GRPCK_RET=${?}
    case "${GRPCK_RET}" in
      2)
        echo "${FUNCNAME}(): \`grpck -r' returned ${GRPCK_RET} (\"one or more bad group entries\"). running \`/usr/bin/yes | /usr/sbin/grpck'."
        # NOTE: this could be dangerous. then again, that is the nature of this whole script.
        /usr/bin/yes | /usr/sbin/grpck
        echo "${FUNCNAME}(): grpck returned ${PIPESTATUS[1]}"
      ;;
      *)
        echo "${FUNCNAME}(): \`grpck -r' returned ${GRPCK_RET}"
      ;;
    esac
  else
    echo "WARNING: grpck not found!" 1>&2
  fi

  return 0
} # user_accounts()
################################################################################
function restart_services() {
  # stuff that needs to be restarted or loaded after patching etc
  #
  # NOTE: at least the following services are not started this way:
  #       - process accounting
  #       - logoutd

  [ -f /etc/sysctl.conf ] &&		/sbin/sysctl -p /etc/sysctl.conf
  [ -x /etc/rc.d/rc.syslog ] &&		/etc/rc.d/rc.syslog	restart
  [ -x /etc/rc.d/rc.firewall ] &&	/etc/rc.d/rc.firewall	restart

  # TODO: enable after making the ssh patch
  #[ -x /etc/rc.d/rc.sshd ] &&		/etc/rc.d/rc.sshd	restart

  return 0
} # restart_services()
################################################################################
function check_and_patch() {
  # $1 = dir
  # $2 = patch file
  # $3 = p level
  # $4 = [reverse]
  local CWD="${PWD}"
  local DIR_TO_PATCH="${1}"
  local PATCH_FILE="${CWD}/${2}"
  local P="${3}"
  local -i GREP_RET
  local -i PATCH_RET
  local -i RET

  [ ! -d "${DIR_TO_PATCH}" ] && {
    echo "${FUNCNAME}(): error: directory \`${DIR_TO_PATCH}' does not exist!" 1>&2
    return 1
  }

  [ ! -f "${PATCH_FILE}" ] && {
    echo "${FUNCNAME}(): error: patch file \`${PATCH_FILE}' does not exist!" 1>&2
    return 1
  }
  #pushd "${1}" || return 1

  set +u
  if [ -n "${4}" -a "${4}" = "reverse" ]
  then
    # this is the best i came up with to detect if the patch is already applied/reversed before actually applying/reversing it.
    # patch seems to return 0 in every case, so we'll have to use grep here.
    echo "${FUNCNAME}(): testing patch file \`${PATCH_FILE##*/}' with --dry-run"
    /usr/bin/patch -R -d "${DIR_TO_PATCH}" -t -p${P} --dry-run -i "${PATCH_FILE}" | /usr/bin/grep "^\(Unreversed patch detected\|The next patch, when reversed, would delete the file\)"
    PATCH_RET=${PIPESTATUS[0]} GREP_RET=${PIPESTATUS[1]}
    [ ${PATCH_RET} -ne 0 -o ${GREP_RET} -eq 0 ] && {
      echo "${FUNCNAME}(): error: patch dry-run didn't work out, maybe the patch has already been reversed?" 1>&2
      return 1
    }
    # if everything was ok, apply the patch
    echo "${FUNCNAME}(): DEBUG: patch would happen"
    /usr/bin/patch -R -d "${DIR_TO_PATCH}" -t -p${P} -i "${PATCH_FILE}"
    RET=${?}
  else
    echo "${FUNCNAME}(): testing patch file \`${PATCH_FILE##*/}' with --dry-run"
    # TODO: detect rej? "3 out of 4 hunks FAILED -- saving rejects to file php.ini.rej"
    /usr/bin/patch -d "${DIR_TO_PATCH}" -t -p${P} --dry-run -i "${PATCH_FILE}" | /usr/bin/grep "^\(The next patch would create the file\|Reversed (or previously applied) patch detected\)"
    PATCH_RET=${PIPESTATUS[0]} GREP_RET=${PIPESTATUS[1]}
    [ ${PATCH_RET} -ne 0 -o ${GREP_RET} -eq 0 ] && {
      echo "${FUNCNAME}(): error: patch dry-run didn't work out, maybe the patch has already been applied?" 1>&2
      return 1
    }
    echo "DEBUG: patch would happen"
    /usr/bin/patch -d "${DIR_TO_PATCH}" -t -p${P} -i "${PATCH_FILE}"
    RET=${?}
  fi
  set -u
  return ${RET}
}
################################################################################
function remove_packages() {
  # BIG FAT NOTE: make sure you don't actually need these!
  #               although, i tried to keep the list short.

  echo "${FUNCNAME}(): removing potentially dangerous packages"

  # CIS 7.1 Disable rhosts Support
  /sbin/removepkg netkit-rsh 2>/dev/null

  # from system-hardening-10.2.txt (Misc Stuff -> Stuff to remove)
  #
  # NOTE: uucp comes with a bunch of SUID binaries, plus i think most people
  #       won't need it nowadays anyway.
  /sbin/removepkg uucp 2>/dev/null

  # remove the floppy package. get rid of the fdmount SUID binary.
  /sbin/removepkg floppy 2>/dev/null

  # TODO: remove xinetd package?

  return 0
} # remove_packages()
################################################################################
function harden_fstab() {
  # related info: http://wiki.centos.org/HowTos/OS_Protection#head-7e30c59c22152e9808c2e0b95ceec1382456d35c

  if [ ! -w /etc ]
  then
    echo "${FUNCNAME}(): error: /etc is not writable. are you sure you are root?" 1>&2
    return 1
  elif [ ! -f /etc/fstab ]
  then
    echo "${FUNCNAME}(): error: /etc/fstab doesn't exist?!?" 1>&2
    return 1
  fi
  # TODO: /tmp and maybe the /var/tmp binding from NSA 2.2.1.4
  gawk '
    # partly from system-hardening-10.2.txt
    # strict settings for filesystems mounted under /mnt
    ( \
      $3 ~ /^(ext[234]|reiserfs|vfat)$/ && \
      $4 !~ /(nodev|nosuid|noexec)/ && \
      ( $2 ~ /^\/m.*/ || $2 ~ /^\/boot/ ) \
    ){
      $4 = $4 ",nosuid,nodev,noexec"
    }
    # from system-hardening-10.2.txt
    ( $2 == "/var" && \
      $4 !~ /(nosuid|nodev)/ \
    ){
      $4 = $4 ",nosuid,nodev"
    }
    # from system-hardening-10.2.txt
    ( $2 == "/home" && \
      $4 !~ /(nosuid|nodev)/ \
    ){
      $4 = $4 ",nosuid,nodev"
    }
    # CIS 6.1 Add 'nodev' Option To Appropriate Partitions In /etc/fstab
    # NOTE:
    #   - added ext4
    #   - this somewhat overlaps with the first rule but the $4 rule takes care of this
    ( \
      $3 ~ /^(ext[234]|reiserfs)$/ && \
      $2 != "/" && \
      $4 !~ /nodev/ \
    ){
      $4 = $4 ",nodev"
    }
    # CIS 6.2 Add 'nosuid' and 'nodev' Option For Removable Media In /etc/fstab
    # NOTE: added noexec
    # NOTE: the "[0-9]?" comes from Debian, where the mount point is /media/cdrom0
    ( \
      $2 ~ /^\/m.*\/(floppy|cdrom[0-9]?)$/ && \
      $4 !~ /(nosuid|nodev|noexec)/ \
    ){
      $4 = $4 ",nosuid,nodev,noexec"
    }
    # NSA RHEL guide - 2.2.1.3.2 Add nodev, nosuid, and noexec Options to /dev/shm
    ( \
      $2 ~ /^\/dev\/shm$/ && \
      $4 !~ /(nosuid|nodev|noexec)/ \
    ){
      $4 = $4 ",nosuid,nodev,noexec"
    }
    {
      # formatting from /usr/lib/setup/SeTpartitions of slackware installer
      if($0 ~ /^#/)
	print
      else
	# slackware format
        #printf "%-16s %-16s %-11s %-16s %-3s %s\n", $1, $2, $3, $4, $5, $6
	# debian format
        printf "%-15s %-15s %-7s %-15s %-7s %s\n", $1, $2, $3, $4, $5, $6
    }' /etc/fstab 1>/etc/fstab.new

  if [ -f /etc/fstab.new ]
  then
    echo "${FUNCNAME}(): /etc/fstab.new created"
  fi

  return ${?}
} # harden_fstab()
################################################################################
function file_permissions() {
  # NOTE: from SYSKLOGD(8):
  #   "Syslogd doesn't change the filemode of opened logfiles at any stage of process.  If a file is created it is world readable.
  #
  # TODO: chmod new log files also

  echo "${FUNCNAME}(): setting file permissions. note that this should be the last function to run."

  # CIS 1.4 Enable System Accounting (applied)
  #
  # NOTE: sysstat was added to slackware at version 11.0
  #
  # NOTE: the etc patch should create the necessary cron entries under /etc/cron.d
  /usr/bin/chmod -c 700 "${SA_RC}"

  # CIS 3.3 Disable GUI Login If Possible (partly)
  /usr/bin/chown -c root:root	/etc/inittab
  /usr/bin/chmod -c 0600	/etc/inittab

  # CIS 4.1 Network Parameter Modifications (partly)
  #
  # NOTE: sysctl.conf should be created by the etc patch
  /usr/bin/chown -c root:root	/etc/sysctl.conf
  /usr/bin/chmod -c 0600	/etc/sysctl.conf

  # CIS 5.3 Confirm Permissions On System Log Files (modified)
  # NOTE: apache -> httpd
  pushd /var/log
  ##############################################################################
  # Permissions for other log files in /var/log
  ##############################################################################
  # NOTE: according to tiger, the permissions of wtmp should be 664
  /usr/bin/chmod -c o-rwx btmp cron* debug* dmesg faillog lastlog maillog* messages* secure* spooler* syslog* wtmp xferlog

  ##############################################################################
  #   directories in /var/log
  ##############################################################################
  /usr/bin/chmod -c o-w httpd cups iptraf nfsd samba sa uucp

  ##############################################################################
  #   contents of directories in /var/log
  ##############################################################################
  /usr/bin/chmod -c o-rwx httpd/* cups/* iptraf/* nfsd/* samba/* sa/* uucp/*

  ##############################################################################
  #   Slackware package management
  ##############################################################################
  #
  # NOTE: Nessus plugin 21745 triggers, if /var/log/packages is not readable
  /usr/bin/chmod -c o-w		packages removed_packages removed_scripts scripts setup
  /usr/bin/chmod -c o-rwx	packages/* removed_packages/* removed_scripts/* scripts/* setup/*

  ##############################################################################
  # Permissions for group log files in /var/log
  ##############################################################################
  # NOTE: removed wtmp from here, it is group (utmp) writable by default and there might be a good reason for that.
  /usr/bin/chmod -c g-wx btmp cron* debug* dmesg faillog lastlog maillog* messages* secure* spooler* syslog* xferlog

  #   directories in /var/log
  /usr/bin/chmod -c g-w httpd cups iptraf nfsd samba sa uucp

  #   contents of directories in /var/log
  /usr/bin/chmod -c g-wx httpd/* cups/* iptraf/* nfsd/* samba/* sa/* uucp/*

  #   Slackware package management
  /usr/bin/chmod -c g-w packages removed_packages removed_scripts scripts setup
  /usr/bin/chmod -c g-wx packages/* removed_packages/* removed_scripts/* scripts/* setup/*

  ##############################################################################
  # Permissions for owner
  ##############################################################################
  #   log files in /var/log
  /usr/bin/chmod u-x btmp cron* debug* dmesg faillog lastlog maillog* messages* secure* spooler* syslog* wtmp xferlog
  #   contents of directories in /var/log
  # NOTE: disabled, these directories might contain subdirectories so u-x doesn't make sense.
  #/usr/bin/chmod u-x httpd/* cups/* iptraf/* nfsd/* samba/* sa/* uucp/*

  #   Slackware package management
  # NOTE: disabled, these directories might contain subdirectories so u-x doesn't make sense.
  #/usr/bin/chmod u-x packages/* removed_packages/* removed_scripts/* scripts/* setup/*

  # Change ownership
  # NOTE: disabled, the ownerships should be correct.
  #/usr/bin/chown -cR root:root .
  #/usr/bin/chown -c uucp uucp
  #/usr/bin/chgrp -c uucp uucp/*
  #/usr/bin/chgrp -c utmp wtmpq

  popd

  # END OF CIS 5.3

  # CIS 6.3 Verify passwd, shadow, and group File Permissions (modified)

  # here's where CIS goes wrong, the permissions by default are:
  # -rw-r----- root/shadow     498 2009-03-08 22:01 etc/shadow.new
  # ...if we go changing that, xlock for instance goes bananas.
  # modified accordingly.
  /usr/bin/chown -c root:root	/etc/passwd /etc/group
  /usr/bin/chmod -c 644		/etc/passwd /etc/group
  /usr/bin/chown -c root:shadow	/etc/shadow
  /usr/bin/chmod -c 440		/etc/shadow

  # CIS 7.3 Create ftpusers Files
  /usr/bin/chown -c root:root	/etc/ftpusers
  /usr/bin/chmod -c 600		/etc/ftpusers

  # CIS 7.5 Restrict at/cron To Authorized Users
  /usr/bin/chown -c root:root	/etc/cron.allow /etc/at.allow
  /usr/bin/chmod -c 400		/etc/cron.allow /etc/at.allow

  # CIS 7.6 Restrict Permissions On crontab Files
  #
  # NOTE: slackware 13.1 doesn't ship with /etc/crontab file
  if [ -f "/etc/crontab" ]
  then
    /usr/bin/chown -c root:root	/etc/crontab
    /usr/bin/chmod -c 400	/etc/crontab
  fi
  /usr/bin/chown -cR root:root	/var/spool/cron
  /usr/bin/chmod -cR go-rwx	/var/spool/cron

  # CIS 7.8 Restrict Root Logins To System Console
  /usr/bin/chown -c root:root	/etc/securetty
  /usr/bin/chmod -c 400		/etc/securetty

  # CIS 7.9 Set LILO Password
  # - also suggested in system-hardening-10.2.txt
  /usr/bin/chown -c root:root	/etc/lilo.conf
  /usr/bin/chmod -c 600		/etc/lilo.conf

  # CIS 8.13 Limit Access To The Root Account From su
  /usr/bin/chown -c root:root	/etc/suauth
  /usr/bin/chmod -c 400		/etc/suauth

  # 8.7 User Home Directories Should Be Mode 750 or More Restrictive (modified)
  user_home_directories_permissions

  # CIS SN.2 Change Default Greeting String For sendmail
  #
  # i'm not sure about this one...
  #
  # ftp://ftp.slackware.com/pub/slackware/slackware-13.1/slackware/MANIFEST.bz2:
  # -rw-r--r-- root/root     60480 2010-04-24 11:44 etc/mail/sendmail.cf.new

  #/usr/bin/chown -c root:bin /etc/mail/sendmail.cf
  #/usr/bin/chmod -c 444 /etc/mail/sendmail.cf

  ##############################################################################
  # from Security Configuration Benchmark For Apache HTTP Server 2.2
  # Version 3.0.0 (CIS_Apache_HTTP_Server_Benchmark_v3.0.0)
  ##############################################################################

  # CIS 1.3.6 Core Dump Directory Security (Level 1, Scorable)
  /usr/bin/chown -c root:apache	/var/log/httpd
  /usr/bin/chmod -c o-rwx	/var/log/httpd

  ##############################################################################
  # from Nessus cert_unix_checklist.audit (Cert UNIX Security Checklist v2.0)
  # http://www.nessus.org/plugins/index.php?view=single&id=21157
  ##############################################################################

  # NOTE: netgroup comes with yptools
  for FILE in \
    "/etc/hosts.equiv" \
    "${INETDCONF}" \
    "/etc/netgroup" \
    "/etc/login.defs" \
    "/etc/login.access"
  do
    [ ! -f "${FILE}" ] && continue
    /usr/bin/chown -c root:root	"${FILE}"
    /usr/bin/chmod -c 600	"${FILE}"
  done

  # Nessus Cert UNIX Security Checklist v2.0 "Permission and ownership check /var/adm/wtmp"
  # UTMP(5): "The  wtmp file records all logins and logouts."
  # LAST,LASTB(1): "Last  searches  back  through the file /var/log/wtmp (or the file designated by the -f flag)
  #                 and displays a list of all users logged in (and out) since that file was created."
  #
  # the default permissions in Slackware are as follows:
  # -rw-rw-r-- root/utmp         0 1994-02-10 19:01 var/log/wtmp.new
  #
  # wtmp offers simply too much detail over so long period of time.
  #
  # NOTE: in slackware 13.1 /var/adm is a symbolic link to /var/log
  /usr/bin/chown -c root:utmp	/var/adm/wtmp
  # rotated files... of course this should be done in logrotate.conf.
  /usr/bin/chown -c root:root	/var/adm/wtmp[.-]*

  # CIS 5.3 handles the permissions, this file shouldn't be readable by all users. it contains sensitive information.
  #/usr/bin/chmod -c 0644	/var/adm/wtmp
  /usr/bin/chmod -c 0600	/var/adm/wtmp[.-]*

  # Nessus CIS_Apache_v2_1.audit "1.19 Updating Ownership and Permissions."
  # ...wtf?
  #/usr/bin/chmod -c 0044 /etc/httpd

  ##############################################################################
  # from system-hardening-10.2.txt:
  ##############################################################################

  # "The file may hold encryption keys in plain text."
  /usr/bin/chmod -c 600		/etc/rc.d/rc.wireless.conf
  /usr/bin/chmod -cR go-rwx	/etc/cron.*

  # "The system startup scripts are world readable by default."
  /usr/bin/chmod -cR go-rwx /etc/rc.d/

  # "Remove the SUID or SGID bit from the following files"
  #
  # NOTE: see CVE-2011-0721 for an example of why.
  #
  # NOTE: you can find all SUID/SGID binaries with "find / -type f \( -perm -04000 -o -perm -02000 \)"
  /usr/bin/chmod -c ug-s	/usr/bin/at
  /usr/bin/chmod -c u-s		/usr/bin/chfn
  /usr/bin/chmod -c u-s		/usr/bin/chsh
  /usr/bin/chmod -c u-s		/usr/bin/crontab
  /usr/bin/chmod -c u-s		/usr/bin/gpasswd
  /usr/bin/chmod -c u-s		/usr/bin/newgrp

  # SSH-KEYSIGN(8):
  # ssh-keysign is disabled by default and can only be enabled in the global client
  # configuration file /etc/ssh/ssh_config by setting EnableSSHKeysign to ``yes''.
  #
  # if you use host based authentication with SSH, you probably need to comment
  # this out.
  #
  # TODO: is the 64bit version somewhere else?

  /usr/bin/chmod -c u-s		/usr/libexec/ssh-keysign

  ##############################################################################
  # end of system-hardening-10.2.txt
  ##############################################################################

  # CUSTOM STUFF BELOW

  # more SUID binaries:
  /usr/bin/chmod -c u-s	/usr/bin/cu
  /usr/bin/chmod -c u-s	/usr/bin/uucp
  #/usr/bin/chmod -c u-s	/usr/bin/pkexec

  # SSA:2011-101-01:
  [ -u /usr/sbin/faillog -o \
    -u /usr/sbin/lastlog ] && {
    echo "${FUNCNAME}(): notice: you seem to be missing a security patch for SSA:2011-101-01"
    /usr/bin/chmod -c u-s	/usr/sbin/faillog
    /usr/bin/chmod -c u-s	/usr/sbin/lastlog
  }

  # the process accounting log file:
  [ -f /var/log/pacct ] && /usr/bin/chmod -c 600 /var/log/pacct

  # adjust the www permissions, so that regular users can't read
  # your database credentials from some php file etc. also so that
  # apache can't write there, in case of some web app vulns.
  [ -d "/var/www" ] && {
    /usr/bin/chown -cR root:apache /var/www
    find /var/www -type d -exec /usr/bin/chmod -c 750 '{}' \;
    find /var/www -type f -exec /usr/bin/chmod -c 640 '{}' \;
  }

  # man 5 limits:
  # "It should be owned by root and readable by root account only."
  [ -f "/etc/limits" ] && {
    /usr/bin/chown -c root:root	/etc/limits
    /usr/bin/chmod -c 600	/etc/limits
  }

  # man 5 audisp-remote.conf:
  # "Note that the key file must be owned by root and mode 0400."
  [ -f "/etc/audisp/audisp-remote.key" ] && {
    /usr/bin/chown -c root:root	/etc/audisp/audisp-remote.key
    /usr/bin/chmod -c 400	/etc/audisp/audisp-remote.key
  }

  # man 5 auditd.conf:
  # "Note that the key file must be owned by root and mode 0400."
  [ -f "/etc/audit/audit.key" ] && {
    /usr/bin/chown -c root:root	/etc/audit/audit.key
    /usr/bin/chmod -c 400	/etc/audit/audit.key
  }

  # sudo: /etc/sudoers is mode 0640, should be 0440
  # visudo -c says: "/etc/sudoers: bad permissions, should be mode 0440"
  /usr/bin/chmod -c 0440 /etc/sudoers

  # there can be SO many log files under /var/log, so i think this is the safest bet.
  # any idea if there's some log files that should be world-readable? for instance Xorg.n.log?
  #
  # NOTE: wtmp has special ownership/permissions which are handled by the etc package (.new)
  #       and logrotate
  /usr/bin/find /var/log -type f -maxdepth 1 \! -name 'wtmp*' -exec /usr/bin/chmod -c 600 '{}' \;
  # we define mindepth here, so /var/log itself doesn't get chmodded. if there are some logs files
  # that need to be written by some other user (for instance tor), it doesn't work if /var/log
  # is with 700 permissions.
  /usr/bin/find /var/log -type d -maxdepth 1 -mindepth 1 -exec /usr/bin/chmod -c 700 '{}' \;

  /usr/bin/find /var/log -type f -name 'wtmp*' -exec /usr/bin/chmod -c 660 '{}' \;

  return 0
} # file_permissions()
################################################################################
function user_home_directories_permissions() {
  # this has been split into it's own function, since it relates to both
  # "hardening categories", user accounts & file permissions.
  local DIR
  # 8.7 User Home Directories Should Be Mode 750 or More Restrictive (modified)
  for DIR in \
    `awk -F: '($3 >= 500) { print $6 }' /etc/passwd` \
    /root
  do
    if [ "x${DIR}" != "x/" ]
    then
      /usr/bin/chmod -c 700 ${DIR}
    fi
  done

  return
} # user_home_directories_permissions()
################################################################################
function create_ftpusers() {
  local NAME
  # CIS 7.3 Create ftpusers Files (modified)
  #
  # FTPUSERS(5):
  #   ftpusers - list of users that may not log in via the FTP daemon
  #
  # NOTE: there's a /etc/vsftpd.ftpusers file described in the CIS document, but
  #       i didn't find any reference to it in vsftpd's own documentation.
  #
  # NOTE: this file is created even if there's no FTP daemon installed.
  #       if proftpd package is installed afterwards, it leaves it's own
  #       ftpusers as .new.
  #
  # NOTE: proftpd's own ftpusers include accounts: ftp, root, uucp & news
  #
  # NOTE: this should be run periodically, since it's a blacklist and
  #       additional user accounts might be created after this.

  # get the login names
  for NAME in `cut -d: -f1 /etc/passwd`
  do
    if [ `id -u $NAME` -lt 500 ]
    then
      # add the name to ftpusers only if it's not already in there.
      # this should work whether the ftpusers file exists already or not.
      grep -q "^${NAME}$" /etc/ftpusers 2>/dev/null || {
	echo "${FUNCNAME}(): adding to /etc/ftpusers: \`${NAME}'"
	echo "${NAME}" 1>> /etc/ftpusers
      }
    fi
  done
  return
} # create_ftpusers()
################################################################################
function set_failure_limits() {
  # from system-hardening-10.2.txt (modified)
  # the UID_MIN and UID_MAX values are from /etc/login.defs
  # disables user accounts after 10 failed logins
  # TODO: periodic
  # TODO: how do we reset this after successful login?
  # NOTE: Debian has this under /usr/bin

  #if [ ! -x /usr/sbin/faillog ]
  #then
  #  echo "error: /usr/sbin/faillog not available!" 1>&2
  #  return 1
  #fi

  echo "${FUNCNAME}(): setting the maximum number of login failures for UIDs ${UID_MIN:-1000}-${UID_MAX:-60000} to ${FAILURE_LIMIT:-10}"

  #/usr/sbin/faillog -u ${UID_MIN:-1000}-${UID_MAX:-60000} -m ${FAILURE_LIMIT:-10}
  faillog -u ${UID_MIN:-1000}-${UID_MAX:-60000} -m ${FAILURE_LIMIT:-10}
  return ${?}
} # set_failure_limits
################################################################################
function miscellaneous_settings() {
  # NOTES:
  #   - it is recommended to run file_permissions() after this function
  #     this function might create some files that don't have secure file permissions
  #
  # TODO:
  #   - tcp_diag module to rc.modules

  create_ftpusers

  # CIS 7.4 Prevent X Server From Listening On Port 6000/tcp (kinda the same)
  [ -f "/usr/bin/startx" ] && sed -i 's/^defaultserverargs=""$/defaultserverargs="-nolisten tcp"/' /usr/bin/startx

  # CIS 7.5 Restrict at/cron To Authorized Users
  #
  # NOTE: the cron.allow file doesn't seem to do anything?!
  #       also, these are created with the patch as necessary.
  #
  # NOTE: if both cron.* are missing, tiger reports this:
  #       --WARN-- [cron005w] Use of cron is not restricted
  #
  # TODO: what's the truth behind dcrond and cron.*?
  #
  #rm -fv /etc/cron.deny /etc/at.deny
  #[ ! -f "/etc/cron.allow" ] &&	echo root 1> /etc/cron.allow
  #[ ! -f "/etc/at.allow" ] &&	echo root 1> /etc/at.allow

  # this is done so the CIS_Apache_v2_1.audit works with Nessus
  # "CIS Recommends removing the default httpd.conf and
  # creating an empty one in /usr/local/apache2/conf."
  #
  # http://www.nessus.org/plugins/index.php?view=single&id=21157
  #
  # NOTE: disabled for now
  #
  # TODO: we need to add a check if apache is even installed
  #mkdir -m 755 -v /usr/local/apache2 && {
  #  ln -sv /etc/httpd /usr/local/apache2/conf
  #  ln -sv /var/log/httpd /usr/local/apache2/logs
  #}

  # END OF CIS

  ##############################################################################
  # from system-hardening-10.2.txt:
  ##############################################################################

  # Account processing is turned on by /etc/rc.d/rc.M.  However, the log file
  # doesn't exist.
  [ ! -f /var/log/pacct ] && touch /var/log/pacct
  # "Don't allow anyone to use at."
  #
  # AT.ALLOW(5): "If the file /etc/at.allow exists, only usernames mentioned in it are allowed to use at."
  #
  # this is also part of CIS 7.5 "Restrict at/cron To Authorized Users"
  #
  # Slackware's at package creates /etc/at.deny by default, which has blacklisted users. so we're switching
  # from blacklist to (empty) whitelist.
  [ -s "/etc/at.deny" -a ! -f "/etc/at.allow" ] && {
    /usr/bin/rm -v	/etc/at.deny
    /usr/bin/touch	/etc/at.allow
  }

  set_failure_limits

  # man 1 xfs
  if [ -f "/etc/X11/fs/config" ]
  then
    sed -i 's/^use-syslog = off$/use-syslog = on/' /etc/X11/fs/config
  fi

  if [ -f "/etc/X11/xdm/Xservers" ]
  then
    sed -i 's/^:0 local \/usr\/bin\/X :0\s*$/:0 local \/usr\/bin\/X -nolisten tcp/' /etc/X11/xdm/Xservers
  fi

  ##############################################################################
  # </system-hardening-10.2.txt>
  ##############################################################################

  # rehash the CA certificates so wget and others can use them
  #[ -d "${CERTS_DIR}" ] && {
  #  pushd "${CERTS_DIR}"
  #  /usr/bin/c_rehash
  #  popd
  #}
  if [ -x /usr/sbin/update-ca-certificates ]
  then
    /usr/sbin/update-ca-certificates -v
  fi

  grep -q "^blacklist ipv6$" /etc/modprobe.d/blacklist.conf 2>/dev/null
  if [ ${?} -ne 0 ]
  then
    echo "# Disable IPv6" 1>>/etc/modprobe.d/blacklist.conf
    echo "blacklist ipv6" 1>>/etc/modprobe.d/blacklist.conf
  fi

  # disable killing of X with Ctrl+Alt+Backspace
  if [ -d /etc/X11/xorg.conf.d ]
  then
    cat 0<<-EOF 1>/etc/X11/xorg.conf.d/99-dontzap.conf
	Section "ServerFlags"
		Option "DontZap" "true"
	EndSection
EOF
#    cat 0<<-EOF 1>/etc/X11/xorg.conf.d/99-cve-2012-0064.conf
#	# see CVE-2012-0064:
#	#   http://seclists.org/oss-sec/2012/q1/191
#	#   http://article.gmane.org/gmane.comp.security.oss.general/6747
#	#   https://bugs.gentoo.org/show_bug.cgi?id=CVE-2012-0064
#	#   http://security-tracker.debian.org/tracker/CVE-2012-0064
#	#   http://packetstormsecurity.org/files/cve/CVE-2012-0064
#	#   http://www.x.org/archive/X11R6.8.1/doc/Xorg.1.html
#	#   http://gu1.aeroxteam.fr/2012/01/19/bypass-screensaver-locker-program-xorg-111-and-up/
#	#   http://who-t.blogspot.com/2012/01/xkb-breaking-grabs-cve-2012-0064.html
#	#   https://lwn.net/Articles/477062/
#	Section "ServerFlags"
#		Option "AllowDeactivateGrabs"	"false"
#		Option "AllowClosedownGrabs"	"false"
#	EndSection
#EOF
  fi

  [ -f /etc/X11/app-defaults/XScreenSaver ] && {
    true
    # TODO: newLoginCommand
  }

  [ -f /etc/X11/xdm/Xresources ] && {
    #echo "xlogin*unsecureGreeting: This is an unsecure session" 1>>/etc/X11/xdm/Xresources
    #echo "xlogin*allowRootLogin: false" 1>>/etc/X11/xdm/Xresources
    true
  }

  return 0
} # miscellaneous settings()
################################################################################
function remove_shells() {
  # see SHELLS(5)
  #
  # NOTES:
  #   - /bin/csh -> tcsh*
  #   - the entries in /etc/shells should be checked periodically, since the
  #     entries are added dynamically from doinst.sh scripts
  local SHELL_TO_REMOVE

  echo "${FUNCNAME}(): removing unnecessary shells"

  # tcsh csh ash ksh zsh	from Slackware
  # es rc esh dash screen	from Debian
  for SHELL_TO_REMOVE in \
    tcsh csh ash ksh zsh \
    es rc esh dash screen
  do
    sed -i '/^\/bin\/'"${SHELL_TO_REMOVE}"'$/d'		/etc/shells
    # for Debian
    sed -i '/^\/usr\/bin\/'"${SHELL_TO_REMOVE}"'$/d'	/etc/shells
  done

  # this is so that we can use this on other systems too...
  if [ -x /sbin/removepkg ]
  then
    for SHELL_TO_REMOVE in tcsh ash ksh93 zsh
    do
      /sbin/removepkg "${SHELL_TO_REMOVE}" 2>/dev/null
    done
  fi

  # see "RESTRICTED SHELL" on BASH(1)
  if [ ! -h /bin/rbash ]
  then
    echo "${FUNCNAME}(): creating rbash link for restricted bash"
    pushd /bin
    ln -sv bash rbash
    popd
  fi

  # add rbash to shells
  grep -q "^/bin/rbash$" /etc/shells || {
    echo "adding rbash to shells"
    echo "/bin/rbash" 1>>/etc/shells
  }

  return 0
} # remove_shells()
################################################################################
function configure_apache() {
  # TODO: under construction!!!
  #   - apply the patch file. also we need arch detection cause httpd.conf has
  #     lib vs. lib64
  #
  # NOTES:
  #   - /var/www ownership and permissions are hardened from file_permissions()

  local -i RET=0
  local    PATCH_FILE="${APACHE_PATCH_FILE}"
  local    MODULES_PATCH_FILE

  [ ! -f "/etc/httpd/httpd.conf" ] && {
    echo "${FUNCNAME}(): warning: apache configuration file \`/etc/httpd/httpd.conf' does not exist, maybe apache is not installed. skipping this part."
    return 0
  }

  [ ! -f "${PATCH_FILE}" ] && {
    echo "${FUNCNAME}(): error: apache hardening patch (\`${PATCH_FILE}') does not exist!" 1>&2
    return 1
  }

  # this is because of lib vs. lib64 directories
  case "${ARCH}" in
    "x86_64")	MODULES_PATCH_FILE="${APACHE_PATCH_MODULES_X86_64_FILE}"	;;
    i?86)	MODULES_PATCH_FILE="${APACHE_PATCH_MODULES_X86_FILE}"		;;
    *)		echo "${FUNCNAME}(): error: unknown architecture \`${ARCH}'!" 1>&2 ;;
  esac

  [ -n "${MODULES_PATCH_FILE}" -a ! -f "${MODULES_PATCH_FILE}" ] && {
    echo "${FUNCNAME}(): error: apache modules hardening patch (\`${MODULES_PATCH_FILE}') does not exist!" 1>&2
    return 1
  }

  check_and_patch /etc/httpd "${MODULES_PATCH_FILE}"	3
  check_and_patch /etc/httpd "${APACHE_PATCH_FILE}"	3

  /usr/sbin/apachectl configtest || {
    echo "${FUNCNAME}(): error: something wen't wrong!" 1>&2
    RET=1
  }
  return ${RET}
} # configure_apache()
################################################################################
# TODO: rename this function
function disable_unnecessary_services() {
  # NOTES:
  #   - this should probably be run only on fresh installations
  #   - this relates to CIS 3.4 "Disable Standard Boot Services"

  # TODO:
  #   - support for sysvinit scripts
  local RC
  local WHILELISTED

  echo "${FUNCNAME}(): disabling and shutting down unnecessary services"

  # go through all the rc scripts
  for RC in /etc/rc.d/rc.*
  do
    # there might also be directories...
    [ ! -f "${RC}" ] && {
      echo "${FUNCNAME}(): DEBUG: \`${RC}' is not a file -> skipping" 1>&2
      continue
    }
    #echo "${FUNCNAME}(): DEBUG: processing \`${RC}'"
    # go through the whitelist
    for WHITELISTED in ${SERVICES_WHITELIST[*]}
    do
      # service is whitelisted, continue with the next $RC
      if [ "${RC}" = "${WHITELISTED}" ]
      then
        echo "${FUNCNAME}(): skipping whitelisted service: \`${RC}'"
        continue 2
      fi
    done
    #echo "${RC} -> NOT WHITELISTED"

    # if it's executable, it's probably running -> shut it down
    [ -x "${RC}" ] && sh "${RC}" stop

    # and then disable it
    /usr/bin/chmod -c 600 "${RC}"
  done

  echo "${FUNCNAME}(): enabling recommended services"

  # CIS 1.4 Enable System Accounting
  /usr/bin/chmod -c 700 "${SA_RC}"

  # CIS 2.2 Configure TCP Wrappers and Firewall to Limit Access (applied)
  #
  # NOTE: the rc.firewall script should be created by the etc patch
  /usr/bin/chmod -c 700 /etc/rc.d/rc.firewall

  # inetd goes with the territory
  disable_inetd_services

  return 0
} # disable_unnecessary_services()
################################################################################
function quick_harden() {
  # this function is designed to do only some basic hardening. so that it can
  # be used in other systems/version that are not directly supported by this
  # script.
  #
  # TODO: under construction

  # configure TCP wrappers
  echo "ALL: ALL EXCEPT localhost" > /etc/hosts.deny

  cat 0<<-EOF 1>>/etc/sysctl.conf
	# Following 11 lines added by CISecurity Benchmark sec 4.1
	net.ipv4.tcp_max_syn_backlog = 4096
	net.ipv4.tcp_syncookies=1
	net.ipv4.conf.all.rp_filter = 1
	net.ipv4.conf.all.accept_source_route = 0
	net.ipv4.conf.all.accept_redirects = 0
	net.ipv4.conf.all.secure_redirects = 0
	net.ipv4.conf.default.rp_filter = 1
	net.ipv4.conf.default.accept_source_route = 0
	net.ipv4.conf.default.accept_redirects = 0
	net.ipv4.conf.default.secure_redirects = 0
	net.ipv4.icmp_echo_ignore_broadcasts = 1
	
	# Following 3 lines added by CISecurity Benchmark sec 4.2
	net.ipv4.ip_forward = 0
	net.ipv4.conf.all.send_redirects = 0
	net.ipv4.conf.default.send_redirects = 0
	
	# following lines are from system-hardening-10.2.txt
	
	# Enable/Disable log spoofed, source routed,redirect packets
	net.ipv4.conf.all.log_martians = 1
	net.ipv4.conf.default.log_martians = 1
	
	# custom
	
	# use address space randomization
	#
	# -plus-
	#
	# Randomizing heap placement makes heap exploits harder, but it
	# also breaks ancient binaries (including anything libc5 based).
	#
	kernel.randomize_va_space = 2
	
	# "Any process which has changed privilege levels or is execute only will not be dumped"
	fs.suid_dumpable = 0
	
	# got the idea from:
	# https://secure.wikimedia.org/wikibooks/en/wiki/Grsecurity/Appendix/Grsecurity_and_PaX_Configuration_Options#Larger_entropy_pools
	kernel.random.poolsize = 8192
	
	# 0 - disable sysrq completely
	# 4 - enable control of keyboard (SAK, unraw)
	# see sysrq.txt from kernel's documentation for details.
	kernel.sysrq = 4
	
	# see Restrict unprivileged access to the kernel syslog (CONFIG_SECURITY_DMESG_RESTRICT) in kernel
	kernel.dmesg_restrict = 1
EOF

  echo "ALL:ALL:DENY" >>/etc/suauth
  chown -c root:root	/etc/suauth
  chmod -c 400		/etc/suauth

  set_failure_limits

  create_ftpusers

  # tested 24.9.2012 against Debian
  remove_shells

  harden_fstab

  return
} # quick_harden()
################################################################################
function patch_sendmail() {
  # $1 = [reverse]

  if [ ! -d "/etc/mail" ]
  then
    echo "${FUNCNAME}(): error: sendmail config dir not found!" 1>&2
    return 1
  elif [ ! -d "${SENDMAIL_CF_DIR}" ]
  then
    echo "${FUNCNAME}(): error: no such directory \`${SENDMAIL_CF_DIR}'! you might not have the sendmail-cf package installed." 1>&2
    return 1
  elif [ ! -f "${SENDMAIL_CF_DIR}/${SENDMAIL_CONF_PREFIX}.mc" ]
  then
    echo "${FUNCNAME}(): error: no such file \`${SENDMAIL_CF_DIR}/${SENDMAIL_CONF_PREFIX}.mc'! you might not have the sendmail-cf package installed." 1>&2
    return 1
  fi

  check_and_patch /usr/share/sendmail "${SENDMAIL_PATCH_FILE}" 1 "${1}" || {
    echo "${FUNCNAME}(): error!" 1>&2
    return 1
  }
  pushd ${SENDMAIL_CF_DIR} || {
    echo "${FUNCNAME}(): error!" 1>&2
    return 1
  }
  # build the config
  sh ./Build "./${SENDMAIL_CONF_PREFIX}.mc" || {
    echo "${FUNCNAME}(): error: error while building the sendmail config!" 1>&2
    popd
    return 1
  }
  [ ! -f "/etc/mail/sendmail.cf.bak" ] && {
    cp -v /etc/mail/sendmail.cf /etc/mail/sendmail.cf.bak
  }
  cp -v "./${SENDMAIL_CONF_PREFIX}.cf" /etc/mail/sendmail.cf
  popd

  # don't reveal the sendmail version
  # no patch file for single line! =)
  sed -i 's/^smtp\tThis is sendmail version \$v$/smtp\tThis is sendmail/' /etc/mail/helpfile

  # if sendmail is running, restart it
  [ -f "/var/run/sendmail.pid" -a -x "/etc/rc.d/rc.sendmail" ] && {
    /etc/rc.d/rc.sendmail restart
  }

  return 0
} # patch_sendmail()
################################################################################
function usage() {
  cat 0<<-EOF
	harden.sh -- system hardening script for slackware linux

	usage: ${0} options

	options:

	  -a	apache
	  -A	all
	  -d	default hardening (misc_settings() & file_permissions())

	  -f	file permissions
	  -F	create/update /etc/ftpusers
	  -g	import Slackware, SBo & other PGP keys to trustedkeys.gpg keyring
	        (you might also want to run this as a regular user)
	  -h	this help
	  -i	disable inetd services
	  -l	set failure limits (faillog) (default value: ${FAILURE_LIMIT:-10})
	  -m	miscellaneous (TODO: remove this? default handles all this)
	  -M	fstab hardening (nodev, nosuid & noexec stuff)

	  patching:

	    -p patch	apply   hardening patch for [patch]
	    -P patch	reverse hardening patch for [patch]

	    available patches:
	      ssh
	      etc
	        the etc patch assumes that you have at least the following packages installed:
		  network-scripts
		  sysvinit-scripts
		  etc
		  shadow
		  logrotate
		  sysklogd
	      apache
	      apache-x86_64 (choose this if you have installed slackware64)
	      sendmail

	  -q	"quick harden" - just some generic stuff that should work on any system
	  -r	remove unnecessary shells
	  -s	disable unnecessary services (also enables few recommended ones)
	  -u	harden user accounts

	functions:

EOF
  # print functions
  #declare -f 2>/dev/null | sed -n '/^.* ().$/s/^/  /p'
  declare -f 2>/dev/null | sed -n '/^.* () $/s/^/  /p'
  exit 0
} # usage()
################################################################################

if [ "${USER}" != "root" ]
then
  echo -e "warning: you should probably be root to run this script\n" 1>&2
fi

while getopts "aAdfFghilmMp:P:qrsu" OPTION
do
  case "${OPTION}" in
    "a") configure_apache		;;
    "A")
      # this is intended to be a all-in-one parameter
      # that you can use on fresh installations

      # NOTES on ordering:
      #   - disabled_unnecessary_services AFTER patch_etc (rc.firewall for instance)

      configure_apache
      user_accounts
      remove_packages
      remove_shells
      import_pgp_keys
      check_and_patch /etc "${ETC_PATCH_FILE}" 1 && ETC_CHANGED=1

      # this should be run after patching etc,
      # there might be new rc scripts.
      disable_unnecessary_services
      #disable_inetd_services

      miscellaneous_settings

      # these should be the last things to run
      file_permissions

      harden_fstab

      # TODO: after restarting syslog,
      # there might be new log files with wrong permissions.
      (( ${ETC_CHANGED} )) && restart_services
    ;;
    "d")
      # default
      miscellaneous_settings
      file_permissions
    ;;
    "f") file_permissions		;;
    "F") create_ftpusers		;;
    "g") import_pgp_keys		;;
    "h")
      usage
      exit 0
    ;;
    "i") disable_inetd_services		;;
    "l") set_failure_limits		;;
    "m")
      # TODO: remove?
      miscellaneous_settings
    ;;
    "M") harden_fstab			;;
    "p")
      case "${OPTARG}" in
	"ssh")
	  # CIS 1.3 Configure SSH
	  check_and_patch /etc/ssh "${SSH_PATCH_FILE}" 1 && \
            [ -f "/var/run/sshd.pid" -a -x "/etc/rc.d/rc.sshd" ] && \
	      /etc/rc.d/rc.sshd restart
	;;
	"etc") check_and_patch /etc "${ETC_PATCH_FILE}" 1 && ETC_CHANGED=1 ;;
        "apache"|"apache-x86_64")
	  case "${OPTARG}" in
            "apache")        check_and_patch /etc/httpd "${APACHE_PATCH_MODULES_X86_FILE}"    3 ;;
            "apache-x86_64") check_and_patch /etc/httpd "${APACHE_PATCH_MODULES_X86_64_FILE}" 3 ;;
	  esac
          check_and_patch /etc/httpd "${APACHE_PATCH_FILE}" 3
	  ;;
	"sendmail")
          patch_sendmail
	;;
	*) echo "error: unknown patch \`${OPTARG}'!" 1>&2 ;;
      esac
    ;;
    "P")
      # reverse a patch
      case "${OPTARG}" in
	"ssh")
	  check_and_patch /etc/ssh "${SSH_PATCH_FILE}" 1 reverse && \
	    [ -f "/var/run/sshd.pid" -a -x "/etc/rc.d/rc.sshd" ] && \
	      /etc/rc.d/rc.sshd restart
	;;
	"etc") check_and_patch /etc "${ETC_PATCH_FILE}" 1 reverse && ETC_CHANGED=1	;;
        "apache"*) echo "apache patch reversing not yet implemented!"			;;
        "sendmail") patch_sendmail reverse						;;
	*)     echo "error: unknown patch \`${OPTARG}'!" 1>&2				;;
      esac
    ;;
    "q") quick_harden			;;
    "r") remove_shells			;;
    "s") disable_unnecessary_services	;;
    "u")
      user_accounts
      set_failure_limits
      create_ftpusers
    ;;
  esac
done

exit 0