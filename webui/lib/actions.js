'use strict';

// webui/lib/actions.js - the web UI's allow-list of privileged actions,
// and how to turn a web form's fields into the exact stdin sequence the
// real bash `action_*` function expects.
//
// Mirrors menus/addon_webui.sh's ALLOWED_ACTIONS array (inside the
// generated kiosk-webui-helper script) - kept in sync by hand rather
// than shared/generated, since both lists are short and deliberately
// curated. A mismatch between the two just means an action fails closed
// on whichever side is missing it, never open on both: server.js checks
// this list before spawning anything, and the helper script re-checks
// its own list before dispatching regardless of what server.js sent.
//
// Every buildStdin() below was verified against the real menus/*.sh
// source (prompt order, defaults, and which fields reject a blank
// answer and re-prompt) - see webui/test/actions.test.js, which drives
// the actual bash functions with this exact output and checks the real
// resulting state (cups_is_installed, lms_is_installed, etc), not just
// that the process exits 0.

const ACTIONS = {
    install_cups: {
        helperAction: 'action_install_cups',
        label: 'Install CUPS Printing',
        fields: [],
        // action_install_cups's only prompt is "Install CUPS printing?
        // (n)" - the web UI's own install button is the confirmation,
        // so this always answers yes. No pause() in this function.
        buildStdin() {
            return 'y\n';
        },
    },

    reconfigure_cups: {
        helperAction: 'action_reconfigure_cups',
        label: 'Reconfigure CUPS for network access',
        fields: [],
        // No prompts at all, no pause().
        buildStdin() {
            return '';
        },
    },

    install_lms: {
        helperAction: 'action_install_lms',
        label: 'Install / reconfigure LMS Server',
        // fields.alreadyInstalled must reflect real current state
        // (server.js fills this in from lms_is_installed via the
        // helper's own status check before offering the reconfigure
        // fields) - action_install_lms branches on it internally and a
        // wrong guess here desyncs the stdin sequence from what the
        // real function actually prompts for.
        fields: ['alreadyInstalled', 'reconfigurePort', 'newPort'],
        buildStdin(f) {
            if (f.alreadyInstalled) {
                if (!f.reconfigurePort) {
                    return 'n\n\n'; // decline reconfigure, then pause()
                }
                const port = Number(f.newPort);
                if (!Number.isInteger(port) || port < 1 || port > 65535) {
                    throw new Error('newPort must be an integer 1-65535');
                }
                return `y\n${port}\n\n`; // accept, new port, pause()
            }
            return '\n'; // fresh install: fully automated except pause()
        },
    },

    install_squeezelite: {
        helperAction: 'action_install_squeezelite',
        label: 'Install / reconfigure Squeezelite Player',
        // If already installed, the real function first asks
        // "Reconfigure?" (default n) and, if declined, returns
        // immediately after just the pause() - it does NOT fall through
        // to the player-name/server prompts. f.reconfigure must be
        // explicit (not inferred from other fields) so the web UI can
        // offer "leave it as-is" without also having to resend the
        // current values.
        fields: ['alreadyInstalled', 'reconfigure', 'playerName', 'lmsServer'],
        buildStdin(f) {
            if (f.alreadyInstalled && !f.reconfigure) {
                return 'n\n\n'; // decline reconfigure, then pause()
            }
            const lines = [];
            if (f.alreadyInstalled) lines.push('y'); // "Reconfigure?"
            lines.push(f.playerName || ''); // blank -> "Kiosk" default
            lines.push(f.lmsServer || ''); // blank -> auto-discovery
            // "Reboot now?" is always answered "n" here regardless of
            // what the UI shows - triggering a real `sudo reboot` from
            // inside a one-click addon-install action is out of scope
            // for this pass (see webui phase-2 plan). The UI surfaces
            // "reboot required to start Squeezelite" as an info banner
            // instead of a real remote reboot trigger.
            lines.push('n');
            lines.push(''); // pause()
            return lines.join('\n') + '\n';
        },
    },

    configure_asterisk_intercom: {
        helperAction: 'action_configure_asterisk_intercom',
        label: 'Configure Asterisk Intercom',
        // Same shape as Squeezelite's reconfigure gate: if already
        // installed, the real function asks "Reconfigure with a
        // different server/extension?" (default n) and returns after
        // just the pause() if declined - the rest of this sequence is
        // never reached in that case.
        fields: ['alreadyInstalled', 'reconfigure', 'serverIp', 'serverPort', 'extension', 'password', 'autoAnswer', 'useTls'],
        buildStdin(f) {
            if (f.alreadyInstalled && !f.reconfigure) {
                return 'n\n\n'; // decline reconfigure, then pause()
            }
            const lines = [];
            // Only present at all when baresip_is_installed is already
            // true - a fresh install has no "Reconfigure?" prompt.
            if (f.alreadyInstalled) lines.push('y');

            // Server IP and extension reject a blank answer and
            // re-prompt (a `while [[ -z ... ]]` loop in the real
            // function) - sending an empty line here would desync the
            // rest of the sequence by consuming a second prompt cycle,
            // so these are validated up front instead.
            if (!f.serverIp || !String(f.serverIp).trim()) throw new Error('serverIp is required');
            lines.push(String(f.serverIp).trim());

            lines.push(f.serverPort != null && f.serverPort !== '' ? String(f.serverPort) : '');

            if (!f.extension || !String(f.extension).trim()) throw new Error('extension is required');
            lines.push(String(f.extension).trim());

            // Password also rejects blank and re-prompts, same reason.
            if (!f.password) throw new Error('password is required');
            lines.push(f.password);

            lines.push(f.autoAnswer ? 'y' : 'n');
            lines.push(f.useTls ? 'y' : 'n');
            // "Proceed with installation?" (default y) - already
            // confirmed by the web click that got us here.
            lines.push('y');
            lines.push(''); // pause()
            return lines.join('\n') + '\n';
        },
    },

    upgrade: {
        helperAction: 'action_upgrade',
        label: 'Check for and apply updates',
        fields: [],
        buildStdin() {
            // action_upgrade's own flow: "Pull these changes...?" (y),
            // then - only if there was anything to pull -
            // "Restart kiosk display now...?" (y), then always
            // "Check for and install the latest Electron...?", answered
            // n here. That sub-flow's own prompts default to declining
            // and aren't a good fit for one-click automation yet (see
            // webui phase-2 plan, "Explicitly deferred"). Answering "n"
            // to a prompt that never actually gets shown (nothing to
            // pull, or the display-restart question) is harmless - a
            // synthesized line bash never reads is simply left unread,
            // not an error.
            return 'y\ny\nn\n';
        },
    },
};

function getAction(name) {
    return Object.prototype.hasOwnProperty.call(ACTIONS, name) ? ACTIONS[name] : undefined;
}

module.exports = { ACTIONS, getAction };
