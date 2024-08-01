#!/usr/bin/env bash

# This is a simple streaming markdown renderer that only perform limited syntax highlighting, designed to handle common cases. It does not support nested syntax highlighting and does not perform full parsing. Therefore the result can be falsy.


if [[ ${TO_TTY} == true ]]; then
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

  : "${STYLE_RESET:=$(tput sgr0)}";
  : "${STYLE_HEADING:=$(tput setaf 12; tput bold)}";
  : "${STYLE_LIST:=$(tput setaf 12)}";
  : "${STYLE_CODE:=$(tput setaf 11)}";
  : "${STYLE_CODE_BLOCK:=""}";
  : "${STYLE_BLOCKQUOTE:=""}";
  : "${STYLE_BOLD:=$(tput setaf 12; tput bold)}";
  : "${STYLE_ITALIC:=$(tput sitm)}";
  : "${STYLE_STRIKETHROUGH:=\e[9m}"; # what is the cap-code of this?
  : "${STYLE_LINK_TEXT:=$(tput setaf 14)}";
  : "${STYLE_URL:=$(tput setaf 12; tput smul)}";
  : "${STYLE_TITLE:=$(tput setaf 2; tput bold)}";
  : "${STYLE_IMAGE_TEXT:=$(tput setaf 14)}";
  : "${STYLE_PUNCTUATION:=$(tput dim)}";

  CURRENT_LINE="";

  function current_style() {
    echo -ne "${STYLE_RESET}";
    if [[ ${IN_LINK_TEXT} == true ]]; then
      echo -ne "${STYLE_LINK_TEXT}";
    elif [[ ${IN_IMAGE_TEXT} == true ]]; then
      echo -ne "${STYLE_IMAGE_TEXT}";
    elif [[ ${IN_HEADING} == true ]]; then
      echo -ne "${STYLE_HEADING}";
    fi
    if [[ ${IN_STRIKETHROUGH} == true ]]; then
      echo -ne "${STYLE_STRIKETHROUGH}";
    fi
    if [[ ${IN_BLOCKQUOTE} == true ]]; then
      echo -ne "${STYLE_BLOCKQUOTE}";
    fi
    if [[ ${IN_BOLD} == true ]]; then
      echo -ne "${STYLE_BOLD}";
    fi
    if [[ ${IN_ITALIC} == true ]]; then
      echo -ne "${STYLE_ITALIC}";
    fi
  }

  buffer="";
  dirty=false;

  while true; do
    if [[ ${dirty} == true ]]; then
      dirty=false;
    else
      IFS= read -r -N 1 char;
      ret=${?};
      if [[ ${ret} -ne 0 ]]; then
        # logging_debug "EOF";
        break;
      fi
      buffer="${buffer}${char}";
    fi
    if [[ "x${char}" == $'x\n' ]]; then
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
      if [[ ${IN_CODE_BLOCK} == true ]]; then
        echo -ne "${STYLE_RESET}${STYLE_CODE_BLOCK}${buffer}";
      else
        echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer}${STYLE_RESET}";
      fi
      buffer="";
      # logging_debug "LINE: ${CURRENT_LINE}";
      CURRENT_LINE="";
    else
      if [[ ${START_OF_LINE} == true ]]; then
        START_OF_LINE=false;
        CURRENT_LINE="${char}";
      else
        CURRENT_LINE="${CURRENT_LINE}${char}";
      fi
      if [[ ${START_OF_CONTENT} != true ]]; then
        # logging_debug "Block mode";
        # logging_debug "$(echo -ne "${buffer}" | hexdump -C | head -n -1)";
        if [[ "x${buffer}" == $'x ' ]]; then
          # logging_debug "Space";
          echo -ne "${buffer}";
          buffer="";
          continue;
        elif [[ "x${buffer}" =~ ^x#+[[:space:]]$ ]]; then
          # logging_debug "Heading mode";
          echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer::-1}${STYLE_RESET}${STYLE_HEADING}";
          buffer="${buffer: -1}";
          IN_HEADING=true;
          START_OF_CONTENT=true;
        elif [[ "x${buffer}" =~ ^x[[:digit:]]+\.[[:space:]]$ ]]; then
          # logging_debug "Ordered list";
          echo -ne "${STYLE_RESET}${STYLE_LIST}${buffer::-1}${STYLE_RESET}";
          buffer="${buffer: -1}";
          IN_LIST=true;
          START_OF_CONTENT=true;
        elif [[ "x${buffer}" =~ ^x(\*|\-|\+)[[:space:]]$ ]]; then
          # logging_debug "Unordered list";
          echo -ne "${STYLE_RESET}${STYLE_LIST}${buffer::-1}${STYLE_RESET}";
          buffer="${buffer: -1}";
          IN_LIST=true;
          START_OF_CONTENT=true;
        elif [[ "x${buffer}" =~ ^x\>$ ]]; then
          # logging_debug "Blockquote mode";
          echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer}${STYLE_RESET}${STYLE_BLOCKQUOTE}";
          buffer="";
          IN_BLOCKQUOTE=true;
          # START_OF_CONTENT=true;
        elif [[ "x${buffer}" =~ ^x\`\`\`$ ]]; then
          if [[ ${IN_CODE_BLOCK} == true ]]; then
            # logging_debug "Code block off";
            IN_CODE_BLOCK=false;
          else
            # logging_debug "Code block mode";
            IN_CODE_BLOCK=true;
          fi
          echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer}${STYLE_RESET}";
          buffer="";
        elif [[ "x${buffer}" =~ ^x((#+)|([[:digit:]]+\.?)|((\*|\-|\+){1,})|(\`\`?)|((\_|\-|\+)+))$ ]]; then
          # logging_debug "Undetermined";
          :
        else
          # logging_debug "Not a block mode";
          START_OF_CONTENT=true;
          dirty=true;
        fi
      fi
      if [[ ${IN_CODE_BLOCK} == true ]]; then
        # logging_debug "Code block mode";
        echo -ne "${buffer}";
        buffer="";
      elif [[ ${START_OF_CONTENT} == true && ${IN_CODE_BLOCK} == false ]]; then
        # logging_debug "Content mode";
        # logging_debug "$(echo -ne "${buffer}" | hexdump -C | head -n -1)";
        if [[ ${IN_CODE} == true && ${IN_ESCAPE} == false ]]; then
          if [[ "x${buffer}" =~ ^x\`$ ]]; then
            # logging_debug "Code off";
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer}$(current_style)";
            IN_CODE=false;
            buffer="";
          else
            echo -ne "${buffer}";
            buffer="";
          fi
        elif [[ ${IN_ESCAPE} == true ]]; then
          # logging_debug "Escape off";
          echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer}$(current_style)";
          IN_ESCAPE=false;
          buffer="";
        elif [[ "x${buffer}" =~ ^x\\$ ]]; then
          IN_ESCAPE=true;
          echo -ne "${buffer}$(current_style)";
          buffer="";
        elif [[ "x${buffer}" == "x " ]]; then
          if [[ ${IN_URL} == true ]]; then
            IN_URL=false;
            IN_TITLE=true;
            # logging_debug "disable URL mode";
            echo -ne "$(current_style)${buffer}";
          else
            echo -ne "${buffer}";
          fi
          buffer="";
        elif [[ "x${buffer}" =~ ^x\*\*\*[^\*]$ || "x${buffer}" =~ ^x___[^_]$ ]]; then
          if [[ ${IN_BOLD} == true && ${IN_ITALIC} == true ]]; then
            # logging_debug "Bold off";
            # logging_debug "Italic off";
            IN_BOLD=false;
            IN_ITALIC=false;
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer::-1}$(current_style)";
          elif [[ ${IN_BOLD} == true ]]; then
            # logging_debug "Bold off";
            # logging_debug "Italic on";
            IN_BOLD=false;
            IN_ITALIC=true;
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer::-1}$(current_style)";
          elif [[ ${IN_ITALIC} == true ]]; then
            # logging_debug "Bold on";
            # logging_debug "Italic off";
            IN_BOLD=true;
            IN_ITALIC=false;
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer::-1}$(current_style)";
          else
            # logging_debug "Bold on";
            # logging_debug "Italic on";
            IN_BOLD=true;
            IN_ITALIC=true;
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer::-1}$(current_style)";
          fi
          buffer="${buffer: -1}";
          dirty=true;
        elif [[ "x${buffer}" =~ ^x\*\*[^\*]$ || "x${buffer}" =~ ^x__[^_]$ ]]; then
          if [[ ${IN_BOLD} == true ]]; then
            # logging_debug "Bold off";
            IN_BOLD=false;
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer::-1}$(current_style)";
          else
            # logging_debug "Bold on";
            IN_BOLD=true;
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer::-1}$(current_style)";
          fi
          buffer="${buffer: -1}";
          dirty=true;
        elif [[ "x${buffer}" =~ ^x\*[^\*]$ || "x${buffer}" =~ ^x_[^_]$ ]]; then
          if [[ ${IN_ITALIC} == true ]]; then
            # logging_debug "Italic off";
            IN_ITALIC=false;
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer::-1}$(current_style)";
          else
            # logging_debug "Italic on";
            IN_ITALIC=true;
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer::-1}$(current_style)";
          fi
          buffer="${buffer: -1}";
          dirty=true;
        elif [[ "x${buffer}" =~ ^x\~\~[^~]$ ]]; then
          if [[ ${IN_STRIKETHROUGH} == true ]]; then
            # logging_debug "Strikethrough off";
            IN_STRIKETHROUGH=false;
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer::-1}$(current_style)";
          else
            # logging_debug "Strikethrough on";
            IN_STRIKETHROUGH=true;
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer::-1}$(current_style)";
          fi
          buffer="${buffer: -1}";
          dirty=true;
        elif [[ "x${buffer}" =~ ^x\`$ ]]; then
          IN_CODE=true;
          echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer}${STYLE_RESET}${STYLE_CODE}";
          buffer="";
        elif [[ "x${buffer}" =~ ^x][^\(]$ ]]; then
          if [[ ${IN_LINK_TEXT} == true ]]; then
            IN_LINK_TEXT=false;
            # logging_debug "Exit link text mode missing URL";
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer::-1}$(current_style)";
            buffer="${buffer: -1}";
            dirty=true;
          elif [[ ${IN_IMAGE_TEXT} == true ]]; then
            IN_LINK_TEXT=false;
            # logging_debug "Exit link text mode missing URL";
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer::-1}$(current_style)";
            buffer="${buffer: -1}";
            dirty=true;
          else
            # logging_debug "']' in the wild";
            echo -ne "${buffer}";
            buffer="";
          fi
        elif [[ "x${buffer}" =~ ^x]\($ ]]; then
          if [[ ${IN_LINK_TEXT} == true ]]; then
            IN_LINK_TEXT=false;
            IN_URL=true;
            # logging_debug "Enter URL mode";
            echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer}${STYLE_RESET}${STYLE_URL}";
            buffer="";
          elif [[ ${IN_IMAGE_TEXT} == true ]]; then
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
        elif [[ "x${buffer}" =~ ^x\[$ ]]; then
          IN_LINK_TEXT=true;
          # logging_debug "Link text mode";
          echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer}${STYLE_RESET}$(current_style)";
          buffer="";
        elif [[ "x${buffer}" =~ ^x\)$ ]]; then
          if [[ ${IN_URL} == true || ${IN_TITLE} == true ]]; then
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
        elif [[ "x${buffer}" =~ ^x\!\[$ ]]; then
          # logging_debug "Image text mode";
          IN_IMAGE_TEXT=true;
          echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer}$(current_style)";
          buffer="";
        elif [[ "x${buffer}" =~ ^x((_)|(~)|(\*)|(\`)|(\!)|(]))+$ ]]; then
          # logging_debug "Undetermined";
          :
        else
          echo -ne "${buffer}";
          buffer="";
        fi
      fi
    fi
    sleep 0;
  done
  echo -ne "${STYLE_RESET}${STYLE_PUNCTUATION}${buffer}${STYLE_RESET}";
else
  # logging_debug "Not a terminal";
  cat;
fi

