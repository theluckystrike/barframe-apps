agentping() {
  [ "$#" -eq 5 ] || { printf '%s\n' 'Use: agentping AGENT KIND TITLE PROJECT SESSION' >&2; return 2; }
  local url
  url=$(/usr/bin/perl -MEncode -e 'use strict; use warnings; die '"'"'Expected six fields'"'"' unless @ARGV == 6; my @keys=qw(agent kind title project session token); sub esc { my $text=decode('"'"'UTF-8'"'"',$_[0],Encode::FB_CROAK); return join('"'"''"'"',map { sprintf('"'"'%%%02X'"'"',$_) } unpack('"'"'C*'"'"',encode('"'"'UTF-8'"'"',$text))); } print '"'"'agentping://event?'"'"'.join('"'"'&'"'"',map { $keys[$_].'"'"'='"'"'.esc($ARGV[$_]) } 0..5);' -- "$@" "${AGENTPING_TOKEN:?Copy the generic snippet from RelayNook Settings}") || return
  /usr/bin/open -g "$url"
}
