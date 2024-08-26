#!/usr/bin/env bash

get_current_column() {
  # https://stackoverflow.com/questions/2575037/how-to-get-the-cursor-position-in-bash
  exec < /dev/tty;
  oldstty="$(stty -g)";
  stty raw -echo min 0;
  echo -ne "\e[6n" > /dev/tty;
  # tput u7 > /dev/tty    # when TERM=xterm (and relatives)
  IFS=';' read -r -d R -a pos;
  stty "${oldstty}";
  echo "$((pos[1] - 1))";
}

if [ "x${TO_TTY}" = "xtrue" ]; then
  # logging_debug "Terminal detected";
  CURR_COL=$(get_current_column);
  BUFFER="";
  # Remaining characters in the of the first line is reduced by $CURR_COL
  LENGTH=$((COLUMNS - CURR_COL));
  LINE_NUM=1;
  while IFS= read -r -N 1 char; do
    if [ "x${char}" = "$(printf 'x\e')" ]; then
      # logging_debug "Consuming escape sequence";
      esc_seq="${char}";
      read -r -N 1 char;
      esc_seq="${esc_seq}${char}";
      if echo "x${char}" | grep -q -E '^x(\[|\()$'; then
        while true; do
          read -r -N 1 char;
          esc_seq="${esc_seq}${char}";
          echo "${char}" | grep -q -E '[a-zA-Z]' && break;
        done
      fi
      BUFFER="${BUFFER}${esc_seq}";
    else
      BUFFER="${BUFFER}${char}";
      LENGTH=$((LENGTH - 1));
    fi
    printf '%s' "${BUFFER}";
    BUFFER="";
    NEWLINE=false;
    if [ "x${char}" = $'x\n' ]; then
      LENGTH=${COLUMNS};
      NEWLINE=true;
    elif [ ${LENGTH} -eq 0 ]; then
      echo;
      LENGTH=${COLUMNS};
      NEWLINE=true;
    fi
    if [ "x${NEWLINE}" = "xtrue" ]; then
      # if we reached the end of the line, increment the line number
      LINE_NUM=$((LINE_NUM+1));
      if [ ${LINE_NUM} -eq ${PAGE_SIZE} ]; then
        read -n 1 -s -r -p "Press any key to continue" < /dev/tty;
        # clear the line and move the cursor to the beginning
        printf '\033[1K\r';
        LINE_NUM=1;
      fi
    fi
  done
else
  # logging_debug "Not a terminal";
  cat -;
fi

