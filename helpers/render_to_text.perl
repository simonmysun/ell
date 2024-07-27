#!/usr/bin/perl

# https://unix.stackexchange.com/questions/14684/removing-control-chars-including-console-codes-colours-from-script-output licensed under CC BY-SA 4.0
# GNU sed and POSIX bash does not support PCRE features like look-ahead. Therefore, adding new a dependency is not avoidable.

while (<>) {
  s/ \e[ #%()*+\-.\/]. |
    \r | # Remove extra carriage returns also
    (?:\e\[|\x9b) [ -?]* [@-~] | # CSI ... Cmd
    (?:\e\]|\x9d) .*? (?:\e\\|[\a\x9c]) | # OSC ... (ST|BEL)
    (?:\e[P^_]|[\x90\x9e\x9f]) .*? (?:\e\\|\x9c) | # (DCS|PM|APC) ... ST
    \e.|[\x80-\x9f] //xg;
    1 while s/[^\b][\b]//g;
  print;
}
