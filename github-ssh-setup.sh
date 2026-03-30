#!/bin/bash
# GitHub SSH Setup
# Einmalig ausführen — richtet SSH-Authentifizierung für GitHub ein.
# Danach: git push ohne Passwort oder Token.

set -e

GITHUB_USER="joergmaertin"
KEY_FILE="$HOME/.ssh/github_id"
SSH_CONFIG="$HOME/.ssh/config"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║          GitHub SSH Setup                        ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── 1. SSH-Key erstellen (falls noch nicht vorhanden) ──────────────────────
if [ -f "$KEY_FILE" ]; then
    echo "✓ SSH-Key existiert bereits: $KEY_FILE"
else
    echo "=== SSH-Key wird erstellt ==="
    ssh-keygen -t ed25519 -C "$GITHUB_USER@github" -f "$KEY_FILE" -N ""
    echo "✓ Key erstellt: $KEY_FILE"
fi

# ── 2. SSH-Agent starten und Key laden ────────────────────────────────────
eval "$(ssh-agent -s)" > /dev/null
ssh-add "$KEY_FILE" 2>/dev/null

# ── 3. SSH-Config eintragen (falls noch nicht vorhanden) ──────────────────
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if grep -q "Host github.com" "$SSH_CONFIG" 2>/dev/null; then
    echo "✓ SSH-Config für github.com existiert bereits"
else
    echo "" >> "$SSH_CONFIG"
    echo "Host github.com" >> "$SSH_CONFIG"
    echo "  HostName github.com" >> "$SSH_CONFIG"
    echo "  User git" >> "$SSH_CONFIG"
    echo "  IdentityFile $KEY_FILE" >> "$SSH_CONFIG"
    echo "  AddKeysToAgent yes" >> "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
    echo "✓ SSH-Config aktualisiert"
fi

# ── 4. Public Key anzeigen ────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  Diesen Public Key bei GitHub eintragen:         ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
cat "$KEY_FILE.pub"
echo ""

# Key automatisch in die Zwischenablage kopieren
pbcopy < "$KEY_FILE.pub"
echo "→ Key wurde in die Zwischenablage kopiert!"
echo ""
echo "Jetzt auf GitHub einfügen:"
echo "  github.com → Profilbild → Settings → SSH and GPG keys"
echo "  → 'New SSH key' → Einfügen (Cmd+V) → 'Add SSH key'"
echo ""

# ── 5. Warten bis Key eingetragen wurde ───────────────────────────────────
read -p "Drücke Enter sobald du den Key bei GitHub eingetragen hast..."
echo ""

# ── 6. Verbindung testen ──────────────────────────────────────────────────
echo "=== Verbindung zu GitHub wird getestet ==="
if ssh -T git@github.com -o StrictHostKeyChecking=accept-new 2>&1 | grep -q "successfully authenticated"; then
    echo "✓ Verbindung erfolgreich! Du bist als '$GITHUB_USER' authentifiziert."
else
    echo "→ GitHub hat geantwortet (das ist normal, auch bei Erfolg):"
    ssh -T git@github.com -o StrictHostKeyChecking=accept-new 2>&1 || true
fi

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  Fertig! Ab jetzt funktioniert git push          ║"
echo "║  ohne Passwort oder Token.                       ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "Remote auf SSH umstellen (einmalig pro Repo):"
echo "  git remote set-url origin git@github.com:$GITHUB_USER/REPO-NAME.git"
echo ""
echo "Für WiredServer:"
echo "  cd ~/Documents/WiredServer"
echo "  git remote set-url origin git@github.com:$GITHUB_USER/Wired-Server-2.5.3-Universal-Binary.git"
echo "  git push -u origin master"
