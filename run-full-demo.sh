#!/bin/bash

set -o errexit

[ ! -f john_doe ] && ssh-keygen -t ed25519 -C "john.doe@example.com" -f john_doe -P ""
[ ! -d signing-demo ] && git clone git@github.com:SubOptimal/signing-demo.git
[ ! -f web-flow.gpg ] && curl -sO https://github.com/web-flow.gpg

allowed_signers_file="$(realpath allowed_signers)"
true > "${allowed_signers_file}"

git config --global gpg.ssh.allowedSignersFile "${allowed_signers_file}"

(
  echo "[*] Prepare John's repository"
  rm -rf signing-john
  git clone signing-demo signing-john
  cd signing-john
  git config commit.gpgsign true
  git config tag.gpgsign true
  git config gpg.format ssh
  git config user.signingkey "$(cut -d ' ' -f 1,2 < ../john_doe.pub)"
  git config user.name "John Doe"
  git config user.email "john.doe@example.com"
)

(
  echo "[*] Commit with John's SSH key"
  eval "$(ssh-agent)"
  ssh-add john_doe
  cd signing-john
  echo "signing john" >> README.md
  git add README.md
  git commit --quiet --message "Signed by John."
  kill -s 9 $SSH_AGENT_PID
)

log_file="$(realpath signing-john.log)"
true > "${log_file}"
(
  echo "[*] Signing log - missing John's signature"
  cd signing-john
  git log --show-signature -2
) |& tee -a "${log_file}"

echo "[*] Add John's public key to allowed signers"
awk '{ print $3,$1,$2 }' < john_doe.pub > allowed_signers

(
  echo "[*] Signing log - with John as allowed signer"
  cd signing-john
  git log --show-signature -2
) |& tee -a "${log_file}"The ""
