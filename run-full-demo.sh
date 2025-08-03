#!/bin/bash

# The script processes all required steps to set up and validate SSH signed commits locally.

set -o errexit

repo_root_dir="$(pwd)"
work_dir="$(realpath signing-work-dir)"
demo_repo_dir="${work_dir}/demo-repo"

if [[ "$1" = "--cleanup" ]]; then
  echo "[*] Cleanup the working directory"
  read -r -p "Remove the working directory '${work_dir}'? [y/N] " response
  response="${response:-n}"
  response="${response:0:1}"
  response="${response,,}"
  if [[ "$response" != "y" ]]; then
    echo "[-] Aborted: The working directory was not removed"
    exit 1
  fi
  echo "[+] Remove the working directory"
  rm -rf "${work_dir}"
  exit
fi

if [[ -d "${demo_repo_dir}" ]]; then
  cat <<HERE
WARNING: The demo repository seems to exist already.
         ${demo_repo_dir}

To avoid data loss or unexpected behaviour the further execution is stopped at this point.

If you want to rerun all steps call the script with the parameter '--cleanup'. This will
remove the sub-directory ./$(basename $work_dir) recursively and all data in it.
HERE
  exit 1
fi

echo "[*] === Preparation steps ==="
mkdir -p "${work_dir}"
echo "[+] Create a SSH key pair for the demo user John Doe"
ssh-keygen -q -t ed25519 -C "john.doe@example.com" -f "${work_dir}/john_doe" -P ""

echo "[+] Create a clone of this repository in the working directory"
git clone --quiet "$(pwd)" "${demo_repo_dir}"

# to avoid repeated downloads after a cleanup, the file is intentionally not downloaded
# into the working directory
if ! [[ -f web-flow.gpg ]]; then
  echo "[+] Download the GitHub GPG public signing key"
  curl -sO https://github.com/web-flow.gpg
echo
  echo "[-] Skipped: GitHub GPG public signing key already downloaded"
fi

echo "[+] Configure demo repository for SSH signing"
cd "${demo_repo_dir}"
# sign all commits and tags by default
git config commit.gpgsign true
git config tag.gpgsign true
# use SSH keys for signing
git config gpg.format ssh
# configure the SSH key to use for signing
git config user.signingkey "$(cut -d ' ' -f 1,2 < ../john_doe.pub)"
# the email address must match the one used for the key pair
git config user.email "john.doe@example.com"
git config user.name "John Doe"

echo "[*] === Process Git actions ==="
echo "[+] Commit with John's SSH key"
cd "${work_dir}"
# for the demo a dedicated SSH agent is used to avoid interference with an already running agent
eval "$(ssh-agent)"
# the used SSH agent needs to know about John's private key
ssh-add john_doe
cd "${demo_repo_dir}"
# do some change and commit it as John
echo "signing john" >> README.md
git add README.md
git commit --quiet --message "Signed by John."
# only needed for the demo agent
kill -s 9 ${SSH_AGENT_PID}

echo "[+] Git log show signature: with allowed signers file not configured"
# error: gpg.ssh.allowedSignersFile needs to be configured and exist for ssh signature verification
cd "${demo_repo_dir}"
git log --show-signature -1

echo "[+] Configure allowed signers file in the repository"
cd "${work_dir}"
allowed_signers_file="$(realpath allowed_signers)"
true > "${allowed_signers_file}"
cd "${demo_repo_dir}"
git config --local gpg.ssh.allowedSignersFile "${allowed_signers_file}"

echo "[+] Git log show signature: with allowed signers file configured"
# Good "git" signature with ED25519 key SHA256:...
# No principal matched.
cd "${demo_repo_dir}"
git log --show-signature -1

echo "[+] Add John's public key to the allowed signers file"
cd "${work_dir}"
awk '{ print $3,$1,$2 }' < john_doe.pub > "${allowed_signers_file}"

echo "[+] Git log show signature: with John's public key added to the allowed signers file"
# Good "git" signature for john.doe@example.com with ED25519 key SHA256:...
cd "${demo_repo_dir}"
git log --show-signature -1

echo "[*] === Process GitHub GPG signed commits ==="
first_commit="$(git rev-list --max-parents=0 HEAD)"
github_fingerprint="968479A1AFF927E37D1A566BB5690EEEBB952194"
# for demonstration purposes the GitHub GPG public signing key is removed from
# the local keyring to show the difference in the output when it is added later
if gpg --list-public-keys |& grep --quiet "${github_fingerprint}"; then
  echo "[+] Delete GitHub GPG public signing key from the local keyring"
  gpg --batch --quiet --delete-key "${github_fingerprint}"
fi
echo "[+] Git log show signature: without GitHub signing key"
cd "${demo_repo_dir}"
git log --show-signature "${first_commit}"

echo "[+] Add GitHub GPG public signing key to the keyring"
cd "${repo_root_dir}"
gpg --quiet --import < web-flow.gpg
echo "[+] Set GitHub owner trust to ultimate"
echo "${github_fingerprint}:6:" | gpg --import-ownertrust --quiet

echo "[+] Git log show signature: with GitHub GPG public signing key added to the keyring"
cd "${demo_repo_dir}"
git log --show-signature "${first_commit}"
