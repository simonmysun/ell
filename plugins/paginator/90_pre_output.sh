#!/usr/bin/env bash

if [[ ${TO_TTY} == true ]]; then
  COLUMNS=$(tput cols);
  PAGE_SIZE=$(tput lines);
  BUFFER="";
  LENGTH=${COLUMNS};
  LINE_NUM=1;
  while IFS= read -r -N 1 char; do
    if [[ "x${char}" == $'x\e' ]]; then
      esc_seq="${char}";
      read -r -N 1 char;
      esc_seq+="${char}";
      if [[ "x${char}" =~ ^x(\[|\()$ ]]; then
        while true; do
          read -r -N 1 char;
          esc_seq+="${char}";
          [[ "${char}" =~ [a-zA-Z] ]] && break;
        done
      fi
      BUFFER="${BUFFER}${esc_seq}";
    else
      BUFFER="${BUFFER}${char}";
      LENGTH=$((LENGTH - 1));
    fi
    echo -ne "${BUFFER}";
    BUFFER="";
    NEWLINE=false;
    if [[ "x${char}" == $'x\n' ]]; then
      LENGTH=${COLUMNS};
      NEWLINE=true;
    elif (( $LENGTH == 0 )); then
      echo;
      LENGTH=${COLUMNS};
      NEWLINE=true;
    fi
    if [[ ${NEWLINE} == true ]]; then
      LINE_NUM=$((LINE_NUM+1));
      if [[ ${LINE_NUM} -eq ${PAGE_SIZE} ]]; then
        read -n 1 -s -r -p "Press any key to continue" < /dev/tty;
        tput el1;
        echo -ne "\r";
        LINE_NUM=1;
      fi
    fi
  done
else
  logging_debug "Not a terminal";
  cat;
fi

