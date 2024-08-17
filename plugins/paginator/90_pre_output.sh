#!/usr/bin/env bash

get_current_column() {
  # https://stackoverflow.com/questions/2575037/how-to-get-the-cursor-position-in-bash
  exec < /dev/tty
  oldstty="$(stty -g)"
  stty raw -echo min 0
  echo -ne "\e[6n" > /dev/tty
  # tput u7 > /dev/tty    # when TERM=xterm (and relatives)
  IFS=';' read -r -d R -a pos
  stty "${oldstty}"
  echo "$((${pos[1]} - 1))"
}

if [[ ${TO_TTY} == true ]]; then
  # logging::debug "Terminal detected";
  CURR_COL=$(get_current_column);
  BUFFER="";
  # Remaining characters in the of the first line is reduced by $CURR_COL
  LENGTH=$((COLUMNS - CURR_COL));
  LINE_NUM=1;
  while IFS= read -r -N 1 char; do
    if [[ "x${char}" == $'x\e' ]]; then
      # logging::debug "Consuming escape sequence";
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
    elif (( ${LENGTH} == 0 )); then
      echo;
      LENGTH=${COLUMNS};
      NEWLINE=true;
    fi
    if [[ ${NEWLINE} == true ]]; then
      # if we reached the end of the line, increment the line number
      LINE_NUM=$((LINE_NUM+1));
      if [[ ${LINE_NUM} -eq ${PAGE_SIZE} ]]; then
        read -n 1 -s -r -p "Press any key to continue" < /dev/tty;
        # clear the line and move the cursor to the beginning
        echo -ne "\e[1K"
        echo -ne "\r";
        LINE_NUM=1;
      fi
    fi
  done
else
  logging::debug "Not a terminal";
  cat -;
fi

