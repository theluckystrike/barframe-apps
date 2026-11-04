#!/bin/sh
set -eu
credential=${AGENTPING_TOKEN:?Copy the install snippet from RelayNook Settings}
mode=${1:?Use waiting, done, or codex}
case "$mode" in waiting|done|codex) ;; *) exit 2 ;; esac
if [ "$mode" = codex ]; then
  payload=${2:?Missing JSON argument}
else
  payload=$(/bin/cat)
fi
url=$(/usr/bin/perl -MJSON::PP -MEncode -e 'use strict; use warnings; my ($payload,$mode,$token)=@ARGV; my $e=decode_json($payload); die '"'"'Expected object'"'"' unless ref($e) eq '"'"'HASH'"'"'; my ($agent,$kind,$title,$session,$project); if($mode eq '"'"'codex'"'"') { exit 0 unless ($e->{type}//'"'"''"'"') eq '"'"'agent-turn-complete'"'"'; ($agent,$kind,$title,$session,$project)=('"'"'Codex CLI'"'"','"'"'done'"'"',$e->{'"'"'last-assistant-message'"'"'}//'"'"'Turn complete'"'"',$e->{'"'"'thread-id'"'"'},$e->{cwd}//'"'"''"'"'); } else { ($agent,$kind,$title,$session,$project)=('"'"'Claude Code'"'"',$mode eq '"'"'waiting'"'"'?'"'"'waiting'"'"':'"'"'done'"'"',$e->{message}//$e->{last_assistant_message}//'"'"'Response complete'"'"',$e->{session_id},$e->{cwd}//'"'"''"'"'); } die '"'"'Missing session'"'"' unless defined($session) && !ref($session) && length($session); die '"'"'Invalid text'"'"' if ref($title) || ref($project); my %f=(agent=>$agent,kind=>$kind,title=>substr($title,0,240),project=>substr($project,0,240),session=>substr($session,0,128),token=>$token); sub esc { return join('"'"''"'"',map { sprintf('"'"'%%%02X'"'"',$_) } unpack('"'"'C*'"'"',encode('"'"'UTF-8'"'"',$_[0]))); } print '"'"'agentping://event?'"'"'.join('"'"'&'"'"',map { $_.'"'"'='"'"'.esc($f{$_}) } qw(agent kind title project session token));' -- "$payload" "$mode" "$credential")
if [ -n "$url" ]; then /usr/bin/open -g "$url"; fi
