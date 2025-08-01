Git commit signing with SSH

The repository is a demo of how to use git commit signing with SSH keys.

The script `run-full-demo.sh` executes all required steps to set up git.

The following steps are executed:
- Generate a new SSH key pair
- Add the public key to the SSH agent
- Configure git to use the SSH key for signing commits
- Create a new commit and sign it with the SSH key
- Verify the signed commit