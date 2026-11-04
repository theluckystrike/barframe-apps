import Foundation

public enum Snippets {
    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    // User-installed hook text uses Perl's data-only JSON parser and UTF-8 encoder.
    // The app never launches this command or requests Apple events.
    public static let hookPerl = #"use strict; use warnings; my ($payload,$mode,$token)=@ARGV; my $e=decode_json($payload); die 'Expected object' unless ref($e) eq 'HASH'; my ($agent,$kind,$title,$session,$project); if($mode eq 'codex') { exit 0 unless ($e->{type}//'') eq 'agent-turn-complete'; ($agent,$kind,$title,$session,$project)=('Codex CLI','done',$e->{'last-assistant-message'}//'Turn complete',$e->{'thread-id'},$e->{cwd}//''); } else { ($agent,$kind,$title,$session,$project)=('Claude Code',$mode eq 'waiting'?'waiting':'done',$e->{message}//$e->{last_assistant_message}//'Response complete',$e->{session_id},$e->{cwd}//''); } die 'Missing session' unless defined($session) && !ref($session) && length($session); die 'Invalid text' if ref($title) || ref($project); my %f=(agent=>$agent,kind=>$kind,title=>substr($title,0,240),project=>substr($project,0,240),session=>substr($session,0,128),token=>$token); sub esc { return join('',map { sprintf('%%%02X',$_) } unpack('C*',encode('UTF-8',$_[0]))); } print 'agentping://event?'.join('&',map { $_.'='.esc($f{$_}) } qw(agent kind title project session token));"#

    public static func urlCommand(payload: String, mode: String, token: String) -> String {
        "/usr/bin/perl -MJSON::PP -MEncode -e " + shellQuote(hookPerl) + " -- " + shellQuote(payload) + " " + shellQuote(mode) + " " + shellQuote(token)
    }
    public static let hookScript = """
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
    url=$(/usr/bin/perl -MJSON::PP -MEncode -e \(shellQuote(hookPerl)) -- "$payload" "$mode" "$credential")
    if [ -n "$url" ]; then /usr/bin/open -g "$url"; fi
    """

    public static func installScript(token: String? = nil) -> String { """
    umask 077
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/agentping-hook" <<'AGENTPING_SCRIPT'
    \(token.map { hookScript.replacingOccurrences(of: "credential=${AGENTPING_TOKEN:?Copy the install snippet from RelayNook Settings}", with: "credential=" + shellQuote($0)) } ?? hookScript)
    AGENTPING_SCRIPT
    chmod 700 "$HOME/.local/bin/agentping-hook"
    """ }

    public static var claudeJSON: String {
        let command = "\"$HOME/.local/bin/agentping-hook\""
        let config: [String: Any] = ["hooks": [
            "Notification": [["matcher": "permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input", "hooks": [["type": "command", "command": command + " waiting"]]]],
            "Stop": [["hooks": [["type": "command", "command": command + " done"]]]]
        ]]
        let data = try! JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
    public static let codexTOML = #"notify = ["sh", "-c", "exec \"$HOME/.local/bin/agentping-hook\" codex \"$1\"", "agentping"]"#
    public static let genericPerl = #"use strict; use warnings; die 'Expected six fields' unless @ARGV == 6; my @keys=qw(agent kind title project session token); sub esc { my $text=decode('UTF-8',$_[0],Encode::FB_CROAK); return join('',map { sprintf('%%%02X',$_) } unpack('C*',encode('UTF-8',$text))); } print 'agentping://event?'.join('&',map { $keys[$_].'='.esc($ARGV[$_]) } 0..5);"#

    public static func genericFunction(token: String? = nil) -> String { """
    agentping() {
      [ "$#" -eq 5 ] || { printf '%s\\n' 'Use: agentping AGENT KIND TITLE PROJECT SESSION' >&2; return 2; }
      local url
      url=$(/usr/bin/perl -MEncode -e \(shellQuote(genericPerl)) -- "$@" \(token.map(shellQuote) ?? "\"${AGENTPING_TOKEN:?Copy the generic snippet from RelayNook Settings}\"")) || return
      /usr/bin/open -g "$url"
    }
    """ }
}
