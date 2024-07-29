#!/usr/bin/env bash

if [[ -t 1 ]]; then
  logging_debug "Terminal width: $(tput cols)";
  logging_debug "Terminal height: $(tput lines)";

  exec 3< <(cat - | stdbuf -o0 fold -w $(tput cols) -s);

  LINE_NUM=0;
  PAGE_SIZE=$(tput lines);
  while IFS= read -r -u 3 line; do
    if [[ ${LINE_NUM} -ge ${PAGE_SIZE} ]]; then
      read -n 1 -s -r -p "Press any key to continue" < /dev/tty;
      tput el1;
      echo -ne "\r";
      LINE_NUM=0;
    fi
    echo $line;
    LINE_NUM=$((LINE_NUM+1));
  done
  exec 3>&-;
else
  logging_debug "Not a terminal";
  cat;
fi

