#!/usr/bin/env bash

# This is a simple streaming markdown renderer that only perform limited syntax highlighting, designed to handle common cases. It does not support nested syntax highlighting and does not perform full parsing. Therefore the result can be falsy.


if [ "x${TO_TTY}" = "xtrue" ]; then
  # logging_debug "Terminal detected. Applying syntax highlighting";

  # Initialize the state machine
  START_OF_LINE=true;
  START_OF_CONTENT=false;
  IN_HEADING=false;
  IN_BLOCKQUOTE=false;
  IN_BOLD=false;
  IN_ITALIC=false;
  IN_STRIKETHROUGH=false;
  IN_CODE=false;
  IN_CODE_BLOCK=false;
  IN_LINK_TEXT=false;
  IN_ESCAPE=false;
  IN_IMAGE_TEXT=false;
  IN_URL=false;
  IN_TITLE=false;

  # Applying defalut styling escape sequences if they are not set
  : "${STYLE_RESET:=$(echo -ne "\e[0m")}";
  : "${STYLE_HEADING:=$(echo -ne "\e[94m\e[1m")}";
  : "${STYLE_LIST:=$(echo -ne "\e[94m")}";
  : "${STYLE_CODE:=$(echo -ne "\e[93m")}";
  : "${STYLE_CODE_BLOCK:=""}";
  : "${STYLE_BLOCKQUOTE:=""}";
  : "${STYLE_BOLD:=$(echo -ne "\e[94m\e[1m")}";
  : "${STYLE_ITALIC:=$(echo -ne "\e[3m")}";
  : "${STYLE_STRIKETHROUGH:==$(echo -ne "\e[9m")}";
  : "${STYLE_LINK_TEXT:=$(echo -ne "\e[96m")}";
  : "${STYLE_URL:=$(echo -ne "\e[94m\e[4m")}";
  : "${STYLE_TITLE:=$(echo -ne "\e[32m\e[1m")}";
  : "${STYLE_IMAGE_TEXT:=$(echo -ne "\e[96m")}";
  : "${STYLE_PUNCTUATION:=$(echo -ne "\e[2m")}";

  CURRENT_LINE="";

  function current_style() {
    # Set the style based on the current state of the syntax highlighting.
    echo -ne "${STYLE_RESET}";
    if [ "x${IN_LINK_TEXT}" = "xtrue" ]; then
      echo -ne "${STYLE_LINK_TEXT}";
    elif [ "x${IN_IMAGE_TEXT}" = "xtrue" ]; then
      echo -ne "${STYLE_IMAGE_TEXT}";
    elif [ "x${IN_HEADING}" = "xtrue" ]; then
      echo -ne "${STYLE_HEADING}";
    fi
    if [ "x${IN_STRIKETHROUGH}" = "xtrue" ]; then
      echo -ne "${STYLE_STRIKETHROUGH}";
    fi
    if [ "x${IN_BLOCKQUOTE}" = "xtrue" ]; then
      echo -ne "${STYLE_BLOCKQUOTE}";
    fi
    if [ "x${IN_BOLD}" = "xtrue" ]; then
      echo -ne "${STYLE_BOLD}";
    fi
    if [ "x${IN_ITALIC}" = "xtrue" ]; then
      echo -ne "${STYLE_ITALIC}";
    fi
  }

  # Input are read into $buffer character by character
  # The state machine is updated when the buffer matches certain patterns
  # if the buffer is not completely consumed, it is marked as dirty and will be processed in the next iteration
  buffer="";
  dirty=false;

  while true; do
    if [ "x${dirty}" = "xtrue" ]; then
      # Skip next read if the buffer is dirty
      dirty=false;
    else
      IFS= read -r -N 1 char;
      if [ ${?} -ne 0 ]; then
        # logging_debug "EOF";
        break;
      fi
      buffer="${buffer}${char}";
    fi
    if [ "x${char}" = $'x\n' ]; then
      # logging_debug "End of line, reseting state";
      START_OF_LINE=true;
      START_OF_CONTENT=false;
      IN_HEADING=false;
      IN_LIST=false;
      IN_BLOCKQUOTE=false;
      IN_BOLD=false;
      IN_ITALIC=false;
      IN_STRIKETHROUGH=false;
      IN_ESCAPE=false;
      IN_CODE=false;
      IN_LINK_TEXT=false;
      IN_URL=false;
      IN_TITLE=false;
      IN_ESCAPE=false;
      IN_IMAGE_TEXT=false;
      if [ "x${IN_CODE_BLOCK}" = "xtrue" ]; then
        echo -ne "${STYLE_RESET}${STYLE_CODE_BLOCK}${buffer}";
      else
        echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer}${STYLE_RESET}";
      fi
      buffer="";
      # logging_debug "LINE: ${CURRENT_LINE}";
      CURRENT_LINE="";
    else
      if [ "x${START_OF_LINE}" = "xtrue" ]; then
        START_OF_LINE=false;
        CURRENT_LINE="${char}";
      else
        CURRENT_LINE="${CURRENT_LINE}${char}";
      fi
      if [ "x${START_OF_CONTENT}" != "xtrue" ]; then
        # logging_debug "Block mode";
        # logging_debug "$(echo -ne "${buffer}" | hexdump -C | head -n -1)";
        if [ "x${buffer}" = 'x ' ]; then
          # logging_debug "Space";
          echo -ne "${buffer}";
          buffer="";
          continue;
        elif echo "x${buffer}" | grep -E -q "^x#{1,}[[:blank:]]$" >/dev/null 2>&1; then
          # logging_debug "Heading mode";
          echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer::${#buffer}-1}${STYLE_RESET}${STYLE_HEADING}";
          buffer="${buffer: -1}";
          IN_HEADING=true;
          START_OF_CONTENT=true;
        elif echo "x${buffer}" | grep -E -q "^x[[:digit:]]+\.[[:space:]]$" >/dev/null 2>&1; then
          # logging_debug "Ordered list";
          echo -ne "${STYLE_RESET}${STYLE_LIST}${buffer::${#buffer}-1}${STYLE_RESET}";
          buffer="${buffer: -1}";
          IN_LIST=true;
          START_OF_CONTENT=true;
        elif [ "x${buffer}" = "x* " ] || [ "x${buffer}" = "x- " ] || [ "x${buffer}" = "x+ " ]; then
          # logging_debug "Unordered list";
          echo -ne "${STYLE_RESET}${STYLE_LIST}${buffer::${#buffer}-1}${STYLE_RESET}";
          buffer="${buffer: -1}";
          IN_LIST=true;
          START_OF_CONTENT=true;
        elif [ "x${buffer}" = "x>" ]; then
          # logging_debug "Blockquote mode";
          echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer}${STYLE_RESET}${STYLE_BLOCKQUOTE}";
          buffer="";
          IN_BLOCKQUOTE=true;
          # START_OF_CONTENT=true;
        elif [ "x${buffer}" = "x\`\`\`" ]; then
          if [ "x${IN_CODE_BLOCK}" = "xtrue" ]; then
            # logging_debug "Code block mode off";
            IN_CODE_BLOCK=false;
          else
            # logging_debug "Code block mode on";
            IN_CODE_BLOCK=true;
          fi
          echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer}${STYLE_RESET}";
          START_OF_CONTENT=true;
          buffer="";
        elif echo "x${buffer}" | grep -E -q "^x#{1,}$" || echo "x${buffer}" | grep -E -q "^x[[:digit:]]{1,}.?$" >/dev/null 2>&1 || echo "x${buffer}" | grep -E -q "^x(\*|\-|\+)+$" >/dev/null 2>&1 || echo "x${buffer}" | grep -E -q "^x\`\`?$" >/dev/null 2>&1 || echo "x${buffer}" | grep -E -q "^x(\_|\-|\+)+$" >/dev/null 2>&1; then
          # logging_debug "Undetermined";
          :
        else
          # logging_debug "Not a block mode";
          START_OF_CONTENT=true;
          dirty=true;
        fi
      fi
      if [ "x${IN_CODE_BLOCK}" = "xtrue" ] && ! echo "x${buffer}" | grep -E -q "^x\`\`?$" >/dev/null 2>&1; then
        # logging_debug "Code block mode";
        echo -ne "${buffer}";
        buffer="";
      elif [ "x${START_OF_CONTENT}" = "xtrue" ] && [ "x${IN_CODE_BLOCK}" = "xfalse" ]; then
        # logging_debug "Content mode";
        # logging_debug "$(echo -ne "${buffer}" | hexdump -C | head -n -1)";
        if [ "x${IN_CODE}" = "xtrue" ] && [ "x${IN_ESCAPE}" = "xfalse" ]; then
          if [ "x${buffer}" = "x\`" ]; then
            # logging_debug "Code off";
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer}$(current_style)";
            IN_CODE=false;
            buffer="";
          else
            echo -ne "${buffer}";
            buffer="";
          fi
        elif [ "x${IN_ESCAPE}" = "xtrue" ]; then
          # logging_debug "Escape off";
          echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer}$(current_style)";
          IN_ESCAPE=false;
          buffer="";
        elif [ "x${buffer}" = "x\\" ]; then
          IN_ESCAPE=true;
          echo -ne "${buffer}$(current_style)";
          buffer="";
        elif [ "x${buffer}" = "x " ]; then
          if [ "x${IN_URL}" = "xtrue" ]; then
            IN_URL=false;
            IN_TITLE=true;
            # logging_debug "disable URL mode";
            echo -ne "$(current_style)${buffer}";
          else
            echo -ne "${buffer}";
          fi
          buffer="";
        elif echo "x${buffer}" | grep -E -q "^x\*\*\*[^\*]$|^x___[^_]$" >/dev/null 2>&1; then
          if [ "x${IN_BOLD}" = "xtrue" ] && [ "x${IN_ITALIC}" = "xtrue" ]; then
            # logging_debug "Bold off";
            # logging_debug "Italic off";
            IN_BOLD=false;
            IN_ITALIC=false;
            printf "%s" "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer%?}$(current_style)";
          elif [ "x${IN_BOLD}" = "xtrue" ]; then
            # logging_debug "Bold off";
            # logging_debug "Italic on";
            IN_BOLD=false;
            IN_ITALIC=true;
            printf "%s" "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer%?}$(current_style)";
          elif [ "x${IN_ITALIC}" = "xtrue" ]; then
            # logging_debug "Bold on";
            # logging_debug "Italic off";
            IN_BOLD=true;
            IN_ITALIC=false;
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer::${#buffer}-1}$(current_style)";
          else
            # logging_debug "Bold on";
            # logging_debug "Italic on";
            IN_BOLD=true;
            IN_ITALIC=true;
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer::${#buffer}-1}$(current_style)";
          fi
          buffer="${buffer: -1}";
          dirty=true;
        elif echo "x${buffer}" | grep -E -q "^x\*\*[^\*]$|^x__[^_]$" >/dev/null 2>&1; then
          if [ "x${IN_BOLD}" = "xtrue" ]; then
            # logging_debug "Bold off";
            IN_BOLD=false;
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer::${#buffer}-1}$(current_style)";
          else
            # logging_debug "Bold on";
            IN_BOLD=true;
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer::${#buffer}-1}$(current_style)";
          fi
          buffer="${buffer: -1}";
          dirty=true;
        elif echo "x${buffer}" | grep -E -q "^x\*[^\*]$|^x_[^_]$" >/dev/null 2>&1; then
          if [ "x${IN_ITALIC}" = "xtrue" ]; then
            # logging_debug "Italic off";
            IN_ITALIC=false;
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer::${#buffer}-1}$(current_style)";
          else
            # logging_debug "Italic on";
            IN_ITALIC=true;
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer::${#buffer}-1}$(current_style)";
          fi
          buffer="${buffer: -1}";
          dirty=true;
        elif echo "x${buffer}" | grep -E -q "^x~~[^~]$" >/dev/null 2>&1; then
          if [ "x${IN_STRIKETHROUGH}" = "xtrue" ]; then
            # logging_debug "Strikethrough off";
            IN_STRIKETHROUGH=false;
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer::${#buffer}-1}$(current_style)";
          else
            # logging_debug "Strikethrough on";
            IN_STRIKETHROUGH=true;
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer::${#buffer}-1}$(current_style)";
          fi
          buffer="${buffer: -1}";
          dirty=true;
        elif [ "x${buffer}" = "x\`" ]; then
          IN_CODE=true;
          echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer}${STYLE_RESET}${STYLE_CODE}";
          buffer="";
        elif echo "x${buffer}" | grep -E -q "^x][^\(]$" >/dev/null 2>&1; then
          if [ "x${IN_LINK_TEXT}" = "xtrue" ]; then
            IN_LINK_TEXT=false;
            # logging_debug "Exit link text mode missing URL";
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer::${#buffer}-1}$(current_style)";
            buffer="${buffer: -1}";
            dirty=true;
          elif [ "x${IN_IMAGE_TEXT}" = "xtrue" ]; then
            IN_LINK_TEXT=false;
            # logging_debug "Exit link text mode missing URL";
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer::${#buffer}-1}$(current_style)";
            buffer="${buffer: -1}";
            dirty=true;
          else
            # logging_debug "']' in the wild";
            echo -ne "${buffer}";
            buffer="";
          fi
        elif [ "x${buffer}" = "x](" ]; then
          if [ "x${IN_LINK_TEXT}" = "xtrue" ]; then
            IN_LINK_TEXT=false;
            IN_URL=true;
            # logging_debug "Enter URL mode";
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer}${STYLE_RESET}${STYLE_URL}";
            buffer="";
          elif [ "x${IN_IMAGE_TEXT}" = "xtrue" ]; then
            IN_IMAGE_TEXT=false;
            IN_URL=true;
            # logging_debug "Enter URL mode";
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer}${STYLE_RESET}${STYLE_URL}";
            buffer="";
          else
            # logging_debug "'](' in the wild";
            echo -ne "${buffer}";
            buffer="";
          fi
        elif [ "x${buffer}" = "x[" ]; then
          IN_LINK_TEXT=true;
          # logging_debug "Link text mode";
          echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer}${STYLE_RESET}$(current_style)";
          buffer="";
        elif [ "x${buffer}" = "x)" ]; then
          if [ "x${IN_URL}" = "xtrue" ] || [ "x${IN_TITLE}" = "xtrue" ]; then
            IN_URL=false;
            IN_TITLE=false;
            # logging_debug "Exit URL or its title mode";
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer}$(current_style)";
            buffer="";
          else
            # logging_debug "')' in the wild";
            echo -ne "${buffer}";
            buffer="";
          fi
          buffer="";
        elif [ "x${buffer}" = "x![" ]; then
          # logging_debug "Image text mode";
          IN_IMAGE_TEXT=true;
          echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer}$(current_style)";
          buffer="";
        elif echo "x${buffer}" | grep -E -q "^x((_)|(~)|(\*)|(\`)|(\!)|(]))+$" >/dev/null 2>&1; then
          # logging_debug "Undetermined";
          :
        else
          echo -ne "${buffer}";
          buffer="";
        fi
      fi
    fi
    # This is a trick to flush the buffer. 
    # Performance is not a concern because the LLM is the bottleneck.
    # Another benefit is that this will make the output more animated.
    sleep 0;
  done
  echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer}${STYLE_RESET}";
else
  # logging_debug "Not a terminal";
  cat -;
fi

