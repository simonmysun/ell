#!/usr/bin/env bash

fold() {
  n="${1:-80}";
  count=0;
  pos=0;
  output="";

  while IFS= read -r -N 1 char; do
    if [[ "x${char}" == $'x\e' ]]; then
      local esc_seq="${char}";
      read -r -N 1 char;
      esc_seq+="$char";
      if [[ "$char" == "[" ]]; then
        while true; do
          read -r -N 1 char;
          esc_seq+="$char";
          [[ "$char" =~ [a-zA-Z] ]] && break;
        done
      fi
      output+="$esc_seq";
    else
      output+="$char";
      count=$((count + 1));
    fi

    echo -ne "$output";
    output="";
    if [[ "$char" == $'\n' ]]; then
      count=0;
    fi
    if (( count >= n )); then
      echo;
      count=0;
    fi
  done
}


if [[ ${TO_TTY} == true ]]; then
  exec 3< <(cat - | fold $(tput cols));

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
    # sleep 0;
  done
  exec 3>&-;
else
  logging_debug "Not a terminal";
  cat;
fi

