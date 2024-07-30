#!/usr/bin/env bash

if [[ -t 1 ]]; then
  exec 3< <(cat - | stdbuf -o0 fold -w $(tput cols) -s);

  LINE_NUM=1;
  PAGE_SIZE=$(tput lines);
  while IFS= read -r -u 3 -N 1 char; do
    echo -ne "${char}";
    if [[ "x${char}" == $'x\n' ]]; then
      LINE_NUM=$((LINE_NUM+1));
      if [[ ${LINE_NUM} -eq ${PAGE_SIZE} ]]; then
        read -n 1 -s -r -p "Press any key to continue" < /dev/tty;
        tput el1;
        echo -ne "\r";
        LINE_NUM=1;
      fi
    fi
    sleep 0;
  done
  exec 3>&-;
else
  logging_debug "Not a terminal";
  cat;
fi

