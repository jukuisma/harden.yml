#!/bin/bash
declare -i ret=0
function download_and_verify() {
  # $1 = file $2 = sig file
  wget -nv "${1}" "${2}"
  ((ret|=${?}))
  gpg --keyring ${keyring} --no-default-keyring --verify $( basename "${2}" ) $( basename "${1}" )
  ((ret|=${?}))
} # download_and_verify()
CWD=$( realpath $( dirname "${0}" ) )
. ${CWD}/../libexec/gpg.sh || exit 1
GPG_KEYRING=$( TMPDIR=~/.gnupg mktemp -t trustedkeys.XXXXXX ) || exit 1
mv -v "${GPG_KEYRING}" "${GPG_KEYRING}.gpg"
GPG_KEYRING+=".gpg"
keyring=$( basename ${GPG_KEYRING} )
declare -r CADIR="/usr/share/ca-certificates/local"
declare -r SKS_CA="sks-keyservers.netCA.pem"
logdir=$( mktemp -p /tmp -d harden.sh.XXXXXX ) || exit 1
#import_pgp_keys
cp -v ~/.gnupg/trustedkeys.uM9yQF.gpg ${GPG_KEYRING}
# TODO: PGP_URLS
for key in ${PGP_KEYS[*]}
do
  # TODO: check if revoked
  gpg --keyring ${keyring} --no-default-keyring --list-keys ${key} 1>/dev/null
  gpg_ret=${?}
  if [ ${gpg_ret} -ne 0 ]
  then
    echo "[-] WARNING: key ${key} not found in the keyring!" 1>&2
  fi
  #((ret|=${gpg_ret}))
done

tmpdir=$( mktemp -p /tmp -d harden.sh.XXXXXX ) || exit 1
pushd ${tmpdir} || exit 1

# test that you can actually verify stuff with the keys
nmap_version="7.60"
download_and_verify https://nmap.org/dist/nmap-${nmap_version}.tar.bz2 https://nmap.org/dist/sigs/nmap-${nmap_version}.tar.bz2.asc

lynis_version="2.5.5"
download_and_verify https://cisofy.com/files/lynis-${lynis_version}.tar.gz https://cisofy.com/files/lynis-${lynis_version}.tar.gz.asc

tiger_version="3.2.3"
download_and_verify http://download.savannah.nongnu.org/releases/tiger/tiger-${tiger_version}.tar.gz http://download.savannah.gnu.org/releases/tiger/tiger-${tiger_version}.tar.gz.sig

psad_version="2.4.5"
download_and_verify http://cipherdyne.org/psad/download/psad-${psad_version}.tar.bz2 http://cipherdyne.org/psad/download/psad-${psad_version}.tar.bz2.asc

mutt_version="1.9.1"
download_and_verify ftp://ftp.mutt.org/pub/mutt/mutt-${mutt_version}.tar.gz ftp://ftp.mutt.org/pub/mutt/mutt-${mutt_version}.tar.gz.asc

arm_version="1.4.5.0"
download_and_verify https://www.atagar.com/arm/resources/static/arm-${arm_version}.tar.bz2 https://www.atagar.com/arm/resources/static/arm-${arm_version}.tar.bz2.asc

modsecurity_version="2.9.2"
download_and_verify https://www.modsecurity.org/tarball/2.9.2/modsecurity-2.9.2.tar.gz https://www.modsecurity.org/tarball/2.9.2/modsecurity-2.9.2.tar.gz.asc

popd
rm -rfv "${tmpdir}"
rm -v "${GPG_KEYRING}"{,~}
exit ${ret}
