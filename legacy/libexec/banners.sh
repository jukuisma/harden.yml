#!/bin/bash
function create_banners() {
  local owner
  local regex
  local file

  print_topic "creating banners"

  (( ${LYNIS_TESTS} )) && local LYNIS_SCORE_BEFORE=$( get_lynis_hardening_index banners )
  for file in /etc/issue /etc/issue.net /etc/motd
  do
    echo "[+] creating ${file}"
    make -f ${CWD}/Makefile ${file}
  done

  if [ -f /etc/gdm3/greeter.dconf-defaults ]
  then
    echo "[+] configuring banner to gdm3"
    for regex in \
      's/^.*banner-message-enable=.*$/banner-message-enable=true/' \
      "s/^.*banner-message-text=.*$/banner-message-text='Authorized uses only.'/"
    do
      sed_with_diff "${regex}" /etc/gdm3/greeter.dconf-defaults
    done
  fi
  # TODO: lightdm

  if [ -f /etc/ssh/sshd_config ]
  then
    echo "[+] configuring banner to sshd"
    sed_with_diff "s/^\(# \?\)\?\(Banner\)\(\s\+\)\S\+$/\2\3\/etc\/issue.net/" /etc/ssh/sshd_config
  fi
  (( ${LYNIS_TESTS} )) && {
    local LYNIS_SCORE_AFTER=$( get_lynis_hardening_index banners )
    compare_lynis_scores "${LYNIS_SCORE_BEFORE}" "${LYNIS_SCORE_AFTER}"
    # BANN-7126 & BANN-7130 will give only partial score because of "Found only 2 key words (5 or more suggested)"
    check_lynis_tests BANN-7124 BANN-7126 BANN-7128 BANN-7130
  }

  return 0
} # create_banners()
