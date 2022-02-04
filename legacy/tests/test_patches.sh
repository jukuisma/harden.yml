#!/bin/bash
################################################################################
# created:	20-07-2013
################################################################################
if [ ${BASH_VERSINFO[0]} -ne 4 ]
then
  echo -e "error: bash version != 4, this script might not work properly!" 1>&2
  echo    "       you can bypass this check by commenting out lines $[${LINENO}-2]-$[${LINENO}+2]." 1>&2
  exit 1
fi
export LANG=en_US
# http://tldp.org/LDP/Bash-Beginners-Guide/html/sect_04_03.html
export LC_ALL=C
# Treat unset variables as an error when substituting.
set -u
for PROGRAM in \
  awk \
  cat \
  cp \
  date \
  gawk \
  grep \
  ln \
  mkdir \
  mktemp \
  mv \
  rm \
  sed \
  shred \
  patch \
  stat
do
  if ! hash "${PROGRAM}" 2>/dev/null
  then
    printf "error: command not found in PATH: %s\n" "${PROGRAM}" >&2
    exit 1
  fi
done
unset PROGRAM
SLACKWARE="slackware"
SLACKWARE="slackware64"
if [ "${SLACKWARE}" = "slackware64" ]
then
  ARCH="x86_64"
else
  ARCH="i486"
fi
SLACKWARE_VERSION="14.2"
JUST_EXPLODE=0
DRY_RUN="--dry-run"
declare -a RET_VALUES=()
declare -a tests=()

if [ -d tmp ]
then
  rm -rf tmp
fi

mkdir -v tmp

for PKG in \
  "a/etc-14.2-${ARCH}-7.txz" \
  "n/network-scripts-14.2-noarch-1.txz" \
  'a/sysvinit-scripts-2.0-noarch-33.txz' \
  "a/sysvinit-functions-8.53-${ARCH}-2.txz" \
  "a/shadow-4.2.1-${ARCH}-1.txz" \
  "a/logrotate-3.8.9-${ARCH}-1.txz" \
  "a/sysklogd-1.5.1-${ARCH}-2.txz" \
  "ap/sudo-1.8.16-${ARCH}-1.txz" \
  'n/sendmail-cf-8.15.2-noarch-2.txz' \
  "n/openssh-7.2p2-${ARCH}-1.txz" \
  "n/php-5.6.23-${ARCH}-1.txz" \
  "n/httpd-2.4.20-${ARCH}-1.txz"
do
  PKG_BASEN=$( basename "${PKG}" )
  if [ ! -f "${PKG_BASEN}" ]
  then
    wget -nv ftp://ftp.slackware.com/pub/slackware/${SLACKWARE}-${SLACKWARE_VERSION}/${SLACKWARE}/${PKG}
  fi
  if [ ! -f "${PKG_BASEN}.asc" ]
  then
    wget -nv ftp://ftp.slackware.com/pub/slackware/${SLACKWARE}-${SLACKWARE_VERSION}/${SLACKWARE}/${PKG}.asc
  fi

  gpgv "${PKG_BASEN}.asc" "${PKG_BASEN}"
  if [ ${?} -ne 0 ]
  then
    echo "WARNING: package verification failed! aborting!" 1>&2
    exit 1
  fi

  pushd tmp
  /sbin/explodepkg ../${PKG_BASEN}
  popd
done

pushd tmp/etc

for CONF in $( find . -name '*.new' )
do
  mv -v "${CONF}" "${CONF%.new}"
  true
done

if (( ${JUST_EXPLODE} ))
then
  exit 0
fi

tests+=("etc")
patch -p1 -t ${DRY_RUN} 0<../../../patches/harden_etc-14.2.patch
RET_VALUE=${?}
RET_VALUES+=( ${RET_VALUE} )
if [ ${RET_VALUE} -ne 0 ]
then
  echo "WARNING: something wrong!" 1>&2
fi
echo -n $'\n'

tests+=("sudoers")
patch -p1 -t ${DRY_RUN} 0<../../../patches/sudoers-1.8.12.patch
RET_VALUE=${?}
RET_VALUES+=( ${RET_VALUE} )
if [ ${RET_VALUE} -ne 0 ]
then
  echo "WARNING: something wrong!" 1>&2
fi
echo -n $'\n'

tests+=("ssh")
patch -p1 -t ${DRY_RUN} 0<../../../patches/ssh_harden-7.1p1.patch
RET_VALUE=${?}
RET_VALUES+=( ${RET_VALUE} )
if [ ${RET_VALUE} -ne 0 ]
then
  echo "WARNING: something wrong!" 1>&2
fi

tests+=("wipe")
patch -p1 -t ${DRY_RUN} 0<../../../patches/wipe.patch
RET_VALUE=${?}
RET_VALUES+=( ${RET_VALUE} )
if [ ${RET_VALUE} -ne 0 ]
then
  echo "WARNING: something wrong!" 1>&2
fi
echo -n $'\n'

tests+=("sendmail")
popd
echo -n $'\n'
pushd tmp/usr/share/sendmail
patch -p1 -t ${DRY_RUN} 0<../../../../../patches/sendmail_harden.patch
RET_VALUE=${?}
RET_VALUES+=( ${RET_VALUE} )
if [ ${RET_VALUE} -ne 0 ]
then
  echo "WARNING: something wrong!" 1>&2
fi
popd

tests+=("php")
pushd tmp/etc/httpd
patch -p1 -t ${DRY_RUN} 0<../../../../patches/php_harden.patch
RET_VALUE=${?}
RET_VALUES+=( ${RET_VALUE} )
if [ ${RET_VALUE} -ne 0 ]
then
  echo "WARNING: something wrong!" 1>&2
fi

tests+=("apache")
patch -p3 -t ${DRY_RUN} 0<../../../../patches/apache_harden.patch
RET_VALUE=${?}
RET_VALUES+=( ${RET_VALUE} )
if [ ${RET_VALUE} -ne 0 ]
then
  echo "WARNING: something wrong!" 1>&2
fi

popd

echo -e "\nresults:"
for ((i=0; i<${#RET_VALUES[*]}; i++))
do
  if [ ${RET_VALUES[i]} -ne 0 ]
  then
    COLOR="\033[0;31m"
  else
    COLOR="\033[0;32m"
  fi
  echo -e "  ${COLOR}${RET_VALUES[i]}\033[0m ${tests[i]}"
done
